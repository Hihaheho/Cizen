defmodule Cizen.Effects.End do
  @moduledoc """
  An effect to end a saga.

  Returns the saga ID.

  ## Example
      saga_id = perform %End{
        saga_id: some_saga_id
      }
  """

  @keys [:saga_id]
  @enforce_keys @keys
  defstruct @keys

  alias Cizen.Effect
  alias Cizen.Saga

  use Effect

  @impl true
  def init(_, %__MODULE__{saga_id: saga_id}) do
    Saga.stop(saga_id)

    {:resolve, saga_id}
  end

  @impl true
  def handle_event(_, _, _, _), do: nil
end
