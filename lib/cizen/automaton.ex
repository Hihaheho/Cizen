defmodule Cizen.Automaton do
  @moduledoc """
  A saga framework to create an automaton.

  Handle requests from `Saga.call/2` and `Saga.cast/2`:

      case perform(%Receive{}) do
        %Automaton.Cast{request: {:push, item}} ->
          [item | state]

        %Automaton.Call{request: :pop, from: from} ->
          [head | tail] = state
          Saga.reply(from, head)
          tail
      end
  """

  alias Cizen.Dispatcher
  alias Cizen.EffectHandler
  alias Cizen.Saga

  alias Cizen.Automaton.{PerformEffect, Yield}

  defmodule Call do
    @moduledoc """
    An event for `Saga.call/2`
    """
    @keys [:request, :from]
    @enforce_keys @keys
    defstruct @keys
  end

  defmodule Cast do
    @moduledoc """
    An event for `Saga.cast/2`
    """
    @keys [:request]
    @enforce_keys @keys
    defstruct @keys
  end

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

  @automaton_pid_key :"$cizen.automaton.automaton_pid"

  defmacro __using__(_opts) do
    quote do
      alias Cizen.Automaton
      import Cizen.Automaton, only: [perform: 1, finish: 0]
      require Cizen.Pattern

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

    {:ok, pid} =
      Task.start_link(fn ->
        Process.put(Saga.saga_id_key(), id)

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

  def handle_call(request, from, handler) do
    feed_event(handler, %Call{request: request, from: from})
  end

  def handle_cast(request, handler) do
    feed_event(handler, %Cast{request: request})
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
