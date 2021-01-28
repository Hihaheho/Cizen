defmodule Cizen.Dispatcher do
  @moduledoc """
  The dispatcher.
  """

  alias Cizen.Dispatcher.{Intake, Node}
  alias Cizen.Event
  alias Cizen.EventType
  alias Cizen.Filter
  alias Cizen.Saga

  require Filter

  @doc false
  def start_link do
    Node.initialize()
    :ets.new(__MODULE__, [:set, :public, :named_table, {:write_concurrency, true}])
    Intake.start_link()
  end

  def log(event, env) do
    # {name, arity} = env.function

    # label =
    #   "#{env.module |> Module.split() |> Enum.drop(1) |> Enum.join(".")}.#{name}/#{arity} #{
    #     env.file |> Path.relative_to(File.cwd!())
    #   }:#{env.line}"

    # time = :os.system_time(:microsecond)
    # :ets.insert(__MODULE__, {{event, label}, time})
  end

  @doc """
  Dispatch the event.
  """
  @spec dispatch(Event.t()) :: :ok
  def dispatch(event) do
    log(event, __ENV__)
    Intake.push(event)
  end

  @doc """
  Listen all events.
  """
  @spec listen_all :: :ok
  def listen_all do
    listen(Filter.new(fn _ -> true end))
  end

  @doc """
  Listen the specific event type.
  """
  @spec listen_event_type(EventType.t()) :: :ok
  def listen_event_type(event_type) do
    listen(Filter.new(fn event -> event.body.__struct__ == event_type end))
  end

  @doc """
  Listen events with the given event filter.
  """
  def listen(event_filter) do
    listen_with_pid(self(), event_filter.code)
  end

  @doc """
  Listen events with the given event filter for the given saga ID.
  """
  def listen(subscriber, event_filter) do
    case Saga.get_pid(subscriber) do
      {:ok, pid} ->
        listen_with_pid(pid, event_filter.code)

      _ ->
        :ok
    end
  end

  defp listen_with_pid(pid, code) do
    Node.put(code, pid)
  end
end
