defmodule Cizen.Effects.Fork do
  @moduledoc """
  An effect to state an saga.

  Returns the started saga ID.

  ## Example
      saga_id = perform %Fork{
        saga: some_saga_struct
      }
  """

  @keys [:saga]
  @enforce_keys @keys
  defstruct @keys

  alias Cizen.Effect
  alias Cizen.Effects.Start

  use Effect

  @impl true
  def expand(id, %__MODULE__{saga: saga}) do
    %Start{saga: saga, lifetime: id}
  end
end
