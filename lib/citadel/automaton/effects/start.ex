defmodule Citadel.Automaton.Effects.Start do
  @moduledoc """
  An effect to request.

  Returns :ok.
  """

  defstruct [:saga]

  alias Citadel.Automaton.Effect
  alias Citadel.Automaton.Effects.{Map, Request}
  alias Citadel.SagaID

  alias Citadel.StartSaga

  @behaviour Effect

  @impl true
  def init(_id, %__MODULE__{saga: saga}) do
    saga_id = SagaID.new()

    effect = %Map{
      effect: %Request{
        body: %StartSaga{id: saga_id, saga: saga}
      },
      transform: fn _ -> saga_id end
    }

    {:alias_of, effect}
  end

  @impl true
  def handle_event(_, _, _, _), do: :ok
end