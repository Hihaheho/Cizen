defmodule Cizen.Effects.Start do
  @moduledoc """
  An effect to start a saga.

  Returns the started saga ID.

  ## Example
      saga_id = perform %Start{
        saga: some_saga_struct
      }
  """

  @keys [:saga]
  @enforce_keys @keys
  defstruct @keys ++ [:lifetime]

  alias Cizen.Dispatcher
  alias Cizen.Effect
  alias Cizen.Filter
  alias Cizen.Saga
  alias Cizen.SagaID

  use Effect
  require Filter

  @impl true
  def init(_, %__MODULE__{saga: saga, lifetime: lifetime}) do
    saga_id = SagaID.new()

    Task.async(fn ->
      Dispatcher.listen(Filter.new(fn %Saga.Started{saga_id: ^saga_id} -> true end))
      Saga.start(saga, saga_id: saga_id, lifetime: lifetime)

      receive do
        %Saga.Started{saga_id: ^saga_id} -> :ok
      end
    end)
    |> Task.await()

    {:resolve, saga_id}
  end

  @impl true
  def handle_event(_, _, _, _), do: nil
end
