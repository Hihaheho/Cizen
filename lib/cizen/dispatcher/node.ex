defmodule Cizen.Dispatcher.Node do
  @moduledoc false
  use GenServer

  alias Cizen.Event
  alias Cizen.Filter
  alias Cizen.Filter.Code

  def initialize do
    :ets.new(__MODULE__, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
  end

  def start_root_node do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_link(parent_node \\ nil) do
    GenServer.start_link(__MODULE__, parent_node)
  end

  @spec push(GenServer.server(), Event.t()) :: MapSet.t(pid)
  def push(node, event) do
    case :ets.lookup(__MODULE__, GenServer.whereis(node)) do
      [{_, state}] ->
        following_nodes =
          state.operations
          |> Enum.reduce([], fn {operation, nodes}, list ->
            case Map.get(nodes, Filter.eval(operation, event)) do
              nil -> list
              node -> [node | list]
            end
          end)

        subscribers =
          Enum.reduce(following_nodes, state.subscribers, fn following_node, subscribers ->
            following_node
            |> __MODULE__.push(event)
            |> MapSet.union(subscribers)
          end)

        subscribers

      [] ->
        MapSet.new([])
    end
  end

  @spec put(GenServer.server(), Code.t(), pid) :: :ok
  def put(node \\ __MODULE__, code, subscriber) do
    run({node, self()}, {:update, code, {:put, subscriber}})

    [:ok]
    |> Stream.cycle()
    |> Enum.reduce_while(0, fn :ok, additional_branches ->
      receive do
        :reached_to_end ->
          if additional_branches == 0 do
            {:halt, :ok}
          else
            {:cont, additional_branches - 1}
          end

        :added_new_branch ->
          {:cont, additional_branches + 1}
      end
    end)
  end

  defp run(ctx, {:update, true, next}) do
    run(ctx, next)
  end

  defp run(ctx, {:update, {:==, [operation, value]}, next})
       when not is_tuple(value) or tuple_size(value) != 2 do
    update_operation(ctx, operation, value, next)
  end

  defp run(ctx, {:update, {:==, [value, operation]}, next})
       when not is_tuple(value) or tuple_size(value) != 2 do
    update_operation(ctx, operation, value, next)
  end

  defp run(ctx, {:update, {:not, [operation]}, next}) do
    update_operation(ctx, operation, false, next)
  end

  defp run(ctx, {:update, {:and, [left, right]}, next}) do
    run(ctx, {:update, left, {:update, right, next}})
  end

  defp run({_node, caller} = ctx, {:update, {:or, [left, right]}, next}) do
    send(caller, :added_new_branch)
    run(ctx, {:update, left, next})
    run(ctx, {:update, right, next})
  end

  defp run(ctx, {:update, operation, next}) do
    update_operation(ctx, operation, true, next)
  end

  defp run({node, caller}, {:put, subscriber}) do
    GenServer.call(node, {:put, subscriber})
    send(caller, :reached_to_end)
  end

  defp update_operation({node, caller}, operation, value, next) do
    GenServer.call(node, {:update_operation, operation, value, next, caller})
  end

  def init(parent_node) do
    state = %{
      parent_node: parent_node,
      operations: %{},
      subscribers: MapSet.new(),
      monitors: %{}
    }

    :ets.insert(__MODULE__, {self(), state})
    {:ok, state}
  end

  def handle_continue(:exit_if_empty, state) do
    if not is_nil(state.parent_node) and empty?(state) do
      GenServer.cast(state.parent_node, {:delete_node, self()})
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, downed_process, _}, state) do
    state = update_in(state.subscribers, &MapSet.delete(&1, downed_process))

    sync(state)

    {:noreply, state, {:continue, :exit_if_empty}}
  end

  def handle_cast({:delete_node, node}, state) do
    if GenServer.call(node, :empty?) do
      GenServer.stop(node, :normal)
      {{operation, value}, state} = pop_in(state, [:monitors, node])

      {_, state} = pop_in(state, [:operations, operation, value])

      state =
        if Enum.empty?(state.operations[operation]) do
          {_, state} = pop_in(state, [:operations, operation])
          state
        else
          state
        end

      sync(state)

      {:noreply, state, {:continue, :exit_if_empty}}
    else
      {:noreply, state}
    end
  catch
    # We can believe here the node is stopped correctly previously.
    :exit, _ ->
      {:noreply, state}
  end

  def handle_call(:empty?, _from, state), do: {:reply, empty?(state), state}

  def handle_call({:put, subscriber}, _from, state) do
    ref = Process.monitor(subscriber)

    state =
      state
      |> update_in([:subscribers], &MapSet.put(&1, subscriber))
      |> put_in([:monitors, ref], :subscriber)

    sync(state)

    {:reply, :ok, state}
  end

  def handle_call({:update_operation, operation, value, next, caller}, from, state) do
    values = Map.get(state.operations, operation, %{})

    {next_node, monitor} =
      case Map.get(values, value) do
        nil ->
          {:ok, node} = start_link(self())
          {node, %{node => {operation, value}}}

        node ->
          {node, %{}}
      end

    # early return
    GenServer.reply(from, :ok)

    run({next_node, caller}, next)

    state =
      state
      |> put_in([:operations, operation], values)
      |> update_in([:monitors], &Map.merge(&1, monitor))
      |> put_in([:operations, operation, value], next_node)

    sync(state)

    {:noreply, state}
  end

  def terminate(_, _) do
    :ets.delete(__MODULE__, self())
  end

  defp empty?(state), do: Enum.empty?(state.operations) and Enum.empty?(state.subscribers)

  defp sync(state) do
    :ets.insert(__MODULE__, {self(), Map.take(state, [:subscribers, :operations])})
  end
end
