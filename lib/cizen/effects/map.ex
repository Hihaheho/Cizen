defmodule Cizen.Effects.Map do
  @moduledoc """
  An effect to transform the result of effect.

  Returns the transformed result.

  ## Example
      perform %Map{
        effect: some_effect,
        transform: fn result -> transformed_result end
      }
  """

  @keys [:effect, :transform]
  @enforce_keys @keys
  defstruct @keys

  alias Cizen.Effect

  use Effect

  @impl true
  def init(id, %__MODULE__{effect: effect, transform: transform}) do
    case Effect.init(id, effect) do
      {:resolve, result} ->
        {:resolve, transform.(result)}

      {effect, other} ->
        {effect, other}
    end
  end

  @impl true
  def handle_event(id, event, %__MODULE__{transform: transform}, {effect, state}) do
    case Effect.handle_event(id, event, effect, state) do
      {:resolve, result} ->
        {:resolve, transform.(result)}

      {:consume, state} ->
        {:consume, {effect, state}}

      other ->
        {effect, other}
    end
  end
end
