defmodule Cizen.Saga do
  @moduledoc """
  The saga behaviour

  ## Example

      defmodule SomeSaga do
        use Cizen.Saga
        defstruct []

        @impl true
        def on_start(%__MODULE__{}) do
          saga
        end

        @impl true
        def handle_event(_event, state) do
          state
        end
      end
  """

  @type t :: struct
  @type state :: any
  # `pid | {atom, node} | atom` is the same as the Process.monitor/1's argument.
  @type lifetime :: pid | {atom, node} | atom | nil

  alias Cizen.CizenSagaRegistry
  alias Cizen.Dispatcher
  alias Cizen.Event
  alias Cizen.Filter
  alias Cizen.SagaID

  require Filter

  @doc """
  Invoked when the saga is started.
  Saga.Started event will be dispatched after this callback.

  Returned value will be used as the next state to pass `c:handle_event/3` callback.
  """
  @callback on_start(t()) :: state

  @doc """
  Invoked when the saga receives an event.

  Returned value will be used as the next state to pass `c:handle_event/3` callback.
  """
  @callback handle_event(Event.t(), state) :: state

  @doc """
  Invoked when the saga is resumed.

  Returned value will be used as the next state to pass `c:handle_event/3` callback.

  This callback is predefined. The default implementation is here:
  ```
  def on_resume(saga, state) do
    on_start(saga)
    state
  end
  ```
  """
  @callback on_resume(t(), state) :: state

  defmacro __using__(_opts) do
    alias Cizen.{CizenSagaRegistry, Dispatcher, Saga}

    quote do
      use GenServer
      @behaviour Saga

      @impl Saga
      def on_resume(saga, state) do
        on_start(saga)
        state
      end

      @impl GenServer
      def init({Saga, :start, id, saga, lifetime}) do
        Saga.init_with(id, saga, lifetime, %Saga.Started{saga_id: id}, :on_start, [
          saga
        ])
      end

      @impl GenServer
      def init({Saga, :resume, id, saga, state, lifetime}) do
        Saga.init_with(id, saga, lifetime, %Saga.Resumed{saga_id: id}, :on_resume, [
          saga,
          state
        ])
      end

      @impl GenServer
      def handle_info({:DOWN, _, :process, _, _}, state) do
        {:stop, {:shutdown, :finish}, state}
      end

      @impl GenServer
      def handle_info(event, state) do
        id = Saga.self()

        case event do
          %Saga.Finish{saga_id: ^id} ->
            {:stop, {:shutdown, :finish}, state}

          event ->
            state = handle_event(event, state)
            {:noreply, state}
        end
      rescue
        reason -> {:stop, {:shutdown, {reason, __STACKTRACE__}}, state}
      end

      @impl GenServer
      def terminate(:shutdown, _state) do
        :shutdown
      end

      def terminate({:shutdown, :finish}, _state) do
        Dispatcher.dispatch(%Saga.Finished{saga_id: Saga.self()})
        :shutdown
      end

      def terminate({:shutdown, {reason, trace}}, _state) do
        id = Saga.self()

        saga =
          case Saga.get_saga(id) do
            {:ok, saga} ->
              saga
              # nil -> should not happen
          end

        Dispatcher.dispatch(%Saga.Crashed{
          saga_id: id,
          saga: saga,
          reason: reason,
          stacktrace: trace
        })

        :shutdown
      end

      @impl GenServer
      def handle_call({Saga, :get_saga_id}, _from, state) do
        [saga_id] = Registry.keys(CizenSagaRegistry, Kernel.self())
        {:reply, saga_id, state}
      end

      def handle_call({Saga, request}, _from, state) do
        result = Saga.handle_request(request)
        {:reply, result, state}
      end

      defoverridable on_resume: 2
    end
  end

  defmodule Finish do
    @moduledoc "A event fired to finish"
    defstruct([:saga_id])
  end

  defmodule Started do
    @moduledoc "A event fired on start"
    defstruct([:saga_id])
  end

  defmodule Resumed do
    @moduledoc "A event fired on resume"
    defstruct([:saga_id])
  end

  defmodule Ended do
    @moduledoc "A event fired on end"
    defstruct([:saga_id])
  end

  defmodule Finished do
    @moduledoc "A event fired on finish"
    defstruct([:saga_id])
  end

  defmodule Crashed do
    @moduledoc "A event fired on crash"
    defstruct([:saga_id, :saga, :reason, :stacktrace])
  end

  @doc """
  Starts a saga which finishes when the current process exits.
  """
  @spec fork(t) :: SagaID.t()
  def fork(%module{} = saga) do
    lifetime = Kernel.self()
    id = SagaID.new()

    {:ok, _pid} = GenServer.start_link(module, {__MODULE__, :start, id, saga, lifetime})

    id
  end

  @doc """
  Starts a saga linked to the current process
  """
  @spec start_link(t) :: GenServer.on_start()
  def start_link(%module{} = saga) do
    id = SagaID.new()
    GenServer.start_link(module, {__MODULE__, :start, id, saga, nil})
  end

  @doc """
  Returns the pid for the given saga ID.
  """
  @spec get_pid(SagaID.t()) :: {:ok, pid} | :error
  defdelegate get_pid(saga_id), to: CizenSagaRegistry

  @doc """
  Returns the saga struct for the given saga ID.
  """
  @spec get_saga(SagaID.t()) :: {:ok, t()} | :error
  defdelegate get_saga(saga_id), to: CizenSagaRegistry

  @lazy_init {__MODULE__, :lazy_init}

  def lazy_init, do: @lazy_init

  @doc """
  Returns the module for a saga.
  """
  @spec module(t) :: module
  def module(saga) do
    saga.__struct__
  end

  @doc """
  Resumes a saga with the given state.
  """
  @spec resume(SagaID.t(), t(), state, pid | nil) :: GenServer.on_start()
  def resume(id, %module{} = saga, state, lifetime \\ nil) do
    GenServer.start(module, {__MODULE__, :resume, id, saga, state, lifetime})
  end

  @spec start_saga(SagaID.t(), t(), pid | nil) :: GenServer.on_start()
  def start_saga(id, saga, lifetime \\ nil)
  def start_saga(id, saga, lifetime) when is_pid(lifetime), do: do_start_saga(id, saga, lifetime)
  def start_saga(id, saga, nil), do: do_start_saga(id, saga, nil)

  def start_saga(id, saga, saga_id) do
    case get_pid(saga_id) do
      {:ok, pid} ->
        do_start_saga(id, saga, pid)

      _ ->
        result = do_start_saga(id, saga, nil)
        end_saga(id)
        result
    end
  end

  defp do_start_saga(id, %module{} = saga, lifetime) do
    {:ok, _pid} = GenServer.start(module, {__MODULE__, :start, id, saga, lifetime})
  end

  @spec end_saga(SagaID.t()) :: :ok
  def end_saga(id) do
    GenServer.stop({:via, Registry, {CizenSagaRegistry, id}}, :shutdown)
  catch
    :exit, _ -> :ok
  after
    Dispatcher.dispatch(%Ended{saga_id: id})
  end

  def send_to(id, message) do
    Registry.dispatch(CizenSagaRegistry, id, fn entries ->
      for {pid, _} <- entries, do: send(pid, message)
    end)
  end

  def exit(id, reason, trace) do
    GenServer.stop({:via, Registry, {CizenSagaRegistry, id}}, {:shutdown, {reason, trace}})
  end

  def call(id, message) do
    GenServer.call({:via, Registry, {CizenSagaRegistry, id}}, message)
  end

  def cast(id, message) do
    GenServer.cast({:via, Registry, {CizenSagaRegistry, id}}, message)
  end

  def self do
    Process.get(:"$cizen.saga_id")
  end

  @doc false
  def init_with(id, saga, lifetime, event, function, arguments) do
    Registry.register(CizenSagaRegistry, id, saga)
    Dispatcher.listen(Filter.new(fn %Finish{saga_id: ^id} -> true end))
    module = module(saga)

    unless is_nil(lifetime), do: Process.monitor(lifetime)

    Process.put(:"$cizen.saga_id", id)

    state =
      case apply(module, function, arguments) do
        {@lazy_init, state} ->
          state

        state ->
          Dispatcher.dispatch(event)
          state
      end

    {:ok, state}
  end

  @doc false
  def handle_request({:register, registry, saga_id, key, value}) do
    Registry.register(registry, key, {saga_id, value})
  end

  def handle_request({:unregister, registry, key}) do
    Registry.unregister(registry, key)
  end

  def handle_request({:unregister_match, registry, key, pattern, guards}) do
    Registry.unregister_match(registry, key, pattern, guards)
  end

  def handle_request({:update_value, registry, key, callback}) do
    Registry.update_value(registry, key, fn {saga_id, value} -> {saga_id, callback.(value)} end)
  end
end
