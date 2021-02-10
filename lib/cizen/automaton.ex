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
  Invoked when last `c:spawn/2` or `c:yield/2` callback returns a next state.

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

      defoverridable spawn: 1, respawn: 2, yield: 1

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
        state = module.yield(state)
        do_yield(module, id, state)
    end
  end

  def start(id, saga) do
    init_with(id, saga, %Saga.Started{saga_id: id}, :spawn, [saga])
  end

  def resume(id, saga, state) do
    init_with(id, saga, %Saga.Resumed{saga_id: id}, :respawn, [saga, state])
  end

  defp init_with(id, saga, event, function, arguments) do
    module = Saga.module(saga)

    pid =
      spawn_link(fn ->
        Process.put(:"$cizen.saga_id", id)

        try do
          state = apply(module, function, arguments)
          Dispatcher.dispatch(event)
          do_yield(module, id, state)
        rescue
          reason -> Saga.exit(id, reason, __STACKTRACE__)
        end
      end)

    handler_state = EffectHandler.init(id)

    {Saga.lazy_init(), {pid, handler_state}}
  end

  def handle_event(%PerformEffect{effect: effect}, {pid, handler}) do
    handle_result(pid, EffectHandler.perform_effect(handler, effect))
  end

  def handle_event(event, state) do
    feed_event(state, event)
  end

  defp feed_event({pid, handler}, event) do
    handle_result(pid, EffectHandler.feed_event(handler, event))
  end

  defp handle_result(pid, {:resolve, value, state}) do
    send(pid, value)
    {pid, state}
  end

  defp handle_result(pid, state) do
    {pid, state}
  end
end
