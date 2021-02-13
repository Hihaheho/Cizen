defmodule Cizen.Automaton do
  @moduledoc """
  A saga framework to create an automaton.
  """

  alias Cizen.Dispatcher
  alias Cizen.EffectHandler
  alias Cizen.Saga

  alias Cizen.Automaton.{PerformEffect, Yield}

  @finish {__MODULE__, :finish}

  def finish, do: @finish

  @type finish :: {__MODULE__, :finish}
  @type state :: term

  @doc """
  Invoked when the automaton is spawned.
  Saga.Started event will be dispatched after this callback.

  Returned value will be used as the next state to pass `c:yield/2` callback.
  Returning `Automaton.finish()` will cause the automaton to finish.

  If not defined, default implementation is used,
  and it passes the given saga struct to `c:yield/2` callback.
  """
  @callback spawn(Saga.t()) :: finish | state

  @doc """
  Invoked when other callbacks returns a next state.

  Returned value will be used as the next state to pass `c:yield/2` callback.
  Returning `Automaton.finish()` will cause the automaton to finish.

  If not defined, default implementation is used,
  and it returns `Automaton.finish()`.
  """
  @callback yield(state) :: finish | state

  @doc """
  Invoked when the automaton is resumed.

  Returned value will be used as the next state to pass `c:yield/2` callback.
  Returning `Automaton.finish()` will cause the automaton to finish.

  This callback is predefined. The default implementation is here:
  ```
  def respawn(saga, state) do
    spawn(saga)
    state
  end
  ```
  """
  @callback respawn(Saga.t(), state) :: finish | state

  @doc """
  Invoked on `Saga.call/2`.

  You should call `Saga.reply/2` with `from`, otherwise the call will be timeout.
  You can reply from any process, at any time.

  Returned value will be used as the next state to pass `c:yield/2` callback.
  Returning `Automaton.finish()` will cause the automaton to finish.
  """
  @callback yield_call(message :: term, GenServer.from(), state) :: finish | state

  @doc """
  Invoked on `Saga.cast/2`.

  Returned value will be used as the next state to pass `c:yield/2` callback.
  Returning `Automaton.finish()` will cause the automaton to finish.
  """
  @callback yield_cast(message :: term, state) :: finish | state

  @automaton_pid_key :"$cizen.automaton.automaton_pid"
  @queue_pid_key :"$cizen.automaton.queue_pid"

  defmacro __using__(_opts) do
    quote do
      alias Cizen.Automaton
      import Cizen.Automaton, only: [perform: 1, finish: 0]
      require Cizen.Filter

      use Saga
      @behaviour Automaton

      @impl Automaton
      def spawn(struct) do
        struct
      end

      @impl Automaton
      def respawn(saga, state) do
        __MODULE__.spawn(saga)
        state
      end

      @impl Automaton
      def yield(_state) do
        finish()
      end

      @impl Automaton
      def yield_call(_message, _from, _state) do
        raise "#{MODULE}.handle_call/2 is not implemented"
      end

      @impl Automaton
      def yield_cast(_message, _state) do
        raise "#{MODULE}.handle_cast/2 is not implemented"
      end

      defoverridable spawn: 1, respawn: 2, yield: 1, yield_call: 3, yield_cast: 2

      @impl Saga
      def on_start(struct) do
        id = Saga.self()
        Automaton.start(id, struct)
      end

      @impl Saga
      def on_resume(struct, state) do
        id = Saga.self()
        Automaton.resume(id, struct, state)
      end

      @impl Saga
      def handle_event(event, state) do
        Automaton.handle_event(event, state)
      end

      @impl Saga
      def handle_call(message, from, state) do
        Automaton.handle_call(message, from, state)
      end

      @impl Saga
      def handle_cast(message, state) do
        Automaton.handle_cast(message, state)
      end
    end
  end

  @doc """
  Performs an effect.

  `perform/1` blocks the current block until the effect is resolved,
  and returns the result of the effect.

  Note that `perform/1` does not work only on the current process.
  """
  def perform(effect) do
    event = %PerformEffect{effect: effect}
    Saga.send_to(Saga.self(), event)

    receive do
      response -> response
    end
  end

  defp do_yield(module, id, state) do
    Dispatcher.dispatch(%Yield{saga_id: id, state: state})

    case state do
      @finish ->
        Dispatcher.dispatch(%Saga.Finish{saga_id: id})

      state ->
        state = handle_queue(module, state)
        state = module.yield(state)
        do_yield(module, id, state)
    end
  end

  defp handle_queue(module, state) do
    @queue_pid_key
    |> Process.get()
    |> Agent.get_and_update(&{&1, []})
    |> Enum.reverse()
    |> Enum.reduce(state, fn
      {:call, message, from}, state ->
        module.yield_call(message, from, state)

      {:cast, message}, state ->
        module.yield_cast(message, state)
    end)
  end

  def start(id, saga) do
    init_with(id, saga, %Saga.Started{saga_id: id}, :spawn, [saga])
  end

  def resume(id, saga, state) do
    init_with(id, saga, %Saga.Resumed{saga_id: id}, :respawn, [saga, state])
  end

  defp init_with(id, saga, event, function, arguments) do
    module = Saga.module(saga)
    {:ok, queue} = Agent.start_link(fn -> [] end)
    Process.put(@queue_pid_key, queue)

    {:ok, pid} =
      Task.start_link(fn ->
        Process.put(Saga.saga_id_key(), id)
        Process.put(@queue_pid_key, queue)

        try do
          state = apply(module, function, arguments)
          Dispatcher.dispatch(event)
          do_yield(module, id, state)
        rescue
          reason -> Saga.exit(id, reason, __STACKTRACE__)
        end
      end)

    Process.put(@automaton_pid_key, pid)
    handler_state = EffectHandler.init(id)
    {Saga.lazy_init(), handler_state}
  end

  def handle_event(%PerformEffect{effect: effect}, handler) do
    handle_result(EffectHandler.perform_effect(handler, effect))
  end

  def handle_event(event, state) do
    feed_event(state, event)
  end

  def handle_call(message, from, handler) do
    pid = Process.get(@queue_pid_key)

    Agent.update(pid, fn queue ->
      [{:call, message, from} | queue]
    end)

    handler
  end

  def handle_cast(message, handler) do
    pid = Process.get(@queue_pid_key)

    Agent.update(pid, fn queue ->
      [{:cast, message} | queue]
    end)

    handler
  end

  defp feed_event(handler, event) do
    handle_result(EffectHandler.feed_event(handler, event))
  end

  defp handle_result({:resolve, value, state}) do
    pid = Process.get(@automaton_pid_key)
    send(pid, value)
    state
  end

  defp handle_result(state), do: state
end
