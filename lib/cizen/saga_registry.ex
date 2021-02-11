defmodule Cizen.SagaRegistry do
  @moduledoc """
  A key-value saga storage.

  It works like `Registry`.
  """

  alias Cizen.Saga
  alias Cizen.SagaID

  @type registry :: Registry.registry()
  @type key :: Registry.key()
  @type value :: Registry.value()
  @type guards :: Registry.guards()
  @type entry :: {SagaID.t(), value}
  @type dispatcher :: ([entry] -> term()) | {module(), atom(), [any()]}

  defdelegate child_spec(options), to: Registry
  defdelegate count(registry), to: Registry
  defdelegate meta(registry, key), to: Registry
  defdelegate put_meta(registry, key, value), to: Registry
  defdelegate start_link(options), to: Registry

  @spec dispatch(registry(), key(), dispatcher(), keyword()) :: :ok
  def dispatch(registry, key, mfa_or_fun, opts \\ []) do
    dispatcher = fn entries ->
      entries = Enum.map(entries, fn {_pid, entry} -> entry end)

      case mfa_or_fun do
        fun when is_function(fun) ->
          fun.(entries)

        {module, function, arguments} ->
          apply(module, function, [entries | arguments])
      end
    end

    Registry.dispatch(registry, key, dispatcher, opts)
  end

  @spec keys(registry(), SagaID.t()) :: [value()]
  def keys(registry, saga_id) do
    case Saga.get_pid(saga_id) do
      {:ok, pid} ->
        Registry.keys(registry, pid)

      _ ->
        []
    end
  end

  @spec lookup(registry(), key()) :: [entry]
  def lookup(registry, key) do
    entries = Registry.lookup(registry, key)
    Enum.map(entries, fn {_pid, entry} -> entry end)
  end

  @spec register(registry(), SagaID.t(), key(), value()) ::
          {:ok, pid()} | {:error, {:already_registered, SagaID.t()}} | {:error, :no_saga}
  def register(registry, saga_id, key, value) do
    result = call_in_saga(saga_id, {:register, registry, saga_id, key, value})

    case result do
      {:error, {:already_registered, pid}} ->
        try do
          saga_id = GenServer.call(pid, {Saga.internal_prefix(), :get_saga_id})
          {:error, {:already_registered, saga_id}}
        catch
          # rare case
          :exit, _ -> register(registry, saga_id, key, value)
        end

      result ->
        result
    end
  end

  @spec unregister(registry(), SagaID.t(), key()) :: :ok | {:error, :no_saga}
  def unregister(registry, saga_id, key) do
    call_in_saga(saga_id, {:unregister, registry, key})
  end

  @spec update_value(registry(), SagaID.t(), key(), (value() -> value())) ::
          {new_value :: term(), old_value :: term()} | {:error, :no_saga}
  def update_value(registry, saga_id, key, callback) do
    call_in_saga(saga_id, {:update_value, registry, key, callback})
  end

  defp call_in_saga(saga_id, request) do
    case Saga.get_pid(saga_id) do
      {:ok, pid} ->
        if pid == self() do
          Saga.handle_request(request)
        else
          try do
            GenServer.call(pid, {Saga.internal_prefix(), :request, request})
          catch
            # rare case
            :exit, _ -> {:error, :no_saga}
          end
        end

      _ ->
        {:error, :no_saga}
    end
  end
end
