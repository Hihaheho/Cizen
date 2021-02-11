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

  alias Cizen.CizenSagaRegistry
  alias Cizen.Dispatcher
  alias Cizen.Event
  alias Cizen.Filter
  alias Cizen.SagaID

  require Filter

  @type t :: struct
  @type state :: any
  # `pid | {atom, node} | atom` is the same as the Process.monitor/1's argument.
  @type lifetime :: pid | {atom, node} | atom | nil
  @type start_option ::
          {:saga_id, SagaID.t()}
          | {:lifetime, pid | SagaID.t() | nil}
          | {:return, :pid | :saga_id}
          | {:resume, term}

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

  @doc """
  The handler for Saga.call(message).

  You should call `Saga.reply/2` with `from`, otherwise the call will be timeout.
  You can reply from any process, at any time.
  """
  @callback handle_call(message :: term, from :: GenServer.from(), state) :: state

  @doc """
  The handler for Saga.cast(message).
  """
  @callback handle_cast(message :: term, state) :: state

  @internal_prefix :"$cizen.saga"
  @saga_id_key :"$cizen.saga.id"
  @lazy_init :"$cizen.saga.lazy_init"

  defmacro __using__(_opts) do
    alias Cizen.{CizenSagaRegistry, Dispatcher, Saga}

    quote do
      @behaviour Saga

      @impl Saga
      def on_resume(saga, state) do
        on_start(saga)
        state
      end

      # @impl GenServer
      def init({:start, id, saga, lifetime}) do
        Saga.init_with(id, saga, lifetime, %Saga.Started{saga_id: id}, :on_start, [
          saga
        ])
      end

      # @impl GenServer
      def init({:resume, id, saga, state, lifetime}) do
        Saga.init_with(id, saga, lifetime, %Saga.Resumed{saga_id: id}, :on_resume, [
          saga,
          state
        ])
      end

      # @impl GenServer
      def handle_info({:DOWN, _, :process, _, _}, state) do
        {:stop, {:shutdown, :finish}, state}
      end

      # @impl GenServer
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

      # @impl GenServer
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

      # @impl GenServer
      @impl Saga
      def handle_call({:"$cizen.saga", :get_saga_id}, _from, state) do
        [saga_id] = Registry.keys(CizenSagaRegistry, Kernel.self())
        {:reply, saga_id, state}
      end

      def handle_call({:"$cizen.saga", :request, request}, _from, state) do
        result = Saga.handle_request(request)
        {:reply, result, state}
      end

      def handle_call({:"$cizen.saga", message}, from, state) do
        state = handle_call(message, from, state)
        {:noreply, state}
      end

      # @impl GenServer
      @impl Saga
      def handle_cast({:"$cizen.saga", :dummy_to_prevent_dialyzer_errors}, state), do: state

      def handle_cast({:"$cizen.saga", message}, state) do
        state = handle_cast(message, state)
        {:noreply, state}
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

  defmodule Finished do
    @moduledoc "A event fired on finish"
    defstruct([:saga_id])
  end

  defmodule Crashed do
    @moduledoc "A event fired on crash"
    defstruct([:saga_id, :saga, :reason, :stacktrace])
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

  Options:
    - `{:lifetime, lifetime_saga_or_pid}` the lifetime saga ID or pid. (Default: the saga lives forever)
    - `{:return, return_type}` when `:saga_id`, `{:ok, saga_id}` is returned. (Default: :pid)
  """
  @spec resume(SagaID.t(), t(), state, [start_option]) :: GenServer.on_start()
  def resume(id, saga, state, opts \\ []) do
    start(saga, Keyword.merge(opts, saga_id: id, resume: state))
  end

  @doc """
  Starts a saga.

  Options:
    - `{:saga_id, saga_id}` starts with the specified saga ID. (Default: randomly generated)
    - `{:lifetime, lifetime_saga_or_pid}` the lifetime saga ID or pid. (Default: the saga lives forever)
    - `{:return, return_type}` when `:saga_id`, `{:ok, saga_id}` is returned. (Default: :pid)
    - `{:resume, state}` when given, resumes the saga with the specified state.
  """
  @spec start(t(), opts :: [start_option]) :: GenServer.on_start()
  def start(%module{} = saga, opts \\ []) do
    {saga_id, return, init} = handle_opts(saga, opts)

    result = GenServer.start(module, init)
    handle_opts_return(result, saga_id, return)
  end

  @doc """
  Starts a saga linked to the current process.

  See `Saga.start/2` for details.
  """
  @spec start_link(t(), opts :: [start_option]) :: GenServer.on_start()
  def start_link(%module{} = saga, opts \\ []) do
    {saga_id, return, init} = handle_opts(saga, opts)

    result = GenServer.start_link(module, init)
    handle_opts_return(result, saga_id, return)
  end

  defp handle_opts(saga, opts) do
    {saga_id, opts} = Keyword.pop(opts, :saga_id, SagaID.new())
    {lifetime, opts} = Keyword.pop(opts, :lifetime, nil)
    {return, opts} = Keyword.pop(opts, :return, :pid)

    mode =
      case Keyword.fetch(opts, :resume) do
        {:ok, state} -> {:resume, state}
        _ -> :start
      end

    opts = Keyword.delete(opts, :resume)

    if opts != [],
      do: raise(ArgumentError, message: "invalid argument(s): #{inspect(Keyword.keys(opts))}")

    lifetime =
      case lifetime do
        nil ->
          nil

        pid when is_pid(pid) ->
          pid

        saga_id ->
          get_lifetime_pid_from_saga_id(saga_id)
      end

    init =
      case mode do
        :start -> {:start, saga_id, saga, lifetime}
        {:resume, state} -> {:resume, saga_id, saga, state, lifetime}
      end

    {saga_id, return, init}
  end

  defp get_lifetime_pid_from_saga_id(saga_id) do
    case get_pid(saga_id) do
      {:ok, pid} -> pid
      _ -> spawn(fn -> nil end)
    end
  end

  defp handle_opts_return(result, saga_id, return) do
    case result do
      {:ok, pid} ->
        {:ok, if(return == :pid, do: pid, else: saga_id)}

      other ->
        other
    end
  end

  @spec stop(SagaID.t()) :: :ok
  def stop(id) do
    GenServer.stop({:via, Registry, {CizenSagaRegistry, id}}, :shutdown)
  catch
    :exit, _ -> :ok
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
    GenServer.call({:via, Registry, {CizenSagaRegistry, id}}, {@internal_prefix, message})
  end

  def cast(id, message) do
    GenServer.cast({:via, Registry, {CizenSagaRegistry, id}}, {@internal_prefix, message})
  end

  def self do
    Process.get(@saga_id_key)
  end

  def reply(from, reply) do
    GenServer.reply(from, reply)
  end

  @doc false
  def init_with(id, saga, lifetime, event, function, arguments) do
    Registry.register(CizenSagaRegistry, id, saga)
    Dispatcher.listen(Filter.new(fn %Finish{saga_id: ^id} -> true end))
    module = module(saga)

    unless is_nil(lifetime), do: Process.monitor(lifetime)

    Process.put(@saga_id_key, id)

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

  @doc false
  def saga_id_key, do: @saga_id_key

  @doc false
  def internal_prefix, do: @internal_prefix
end
