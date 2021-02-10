defmodule Cizen.Effects.All do
  @moduledoc """
  An effect to perform multiple effects.

  Returns the list of resolved values.

  ## Example
        [result1, result2] = perform %All{
          effects: [effect1, effect2]
        }
  """

  @keys [:effects]
  @enforce_keys @keys
  defstruct @keys

  alias Cizen.Effect

  use Effect

  @impl true
  def init(id, %__MODULE__{effects: effects}) do
    {state, resolved} =
      Enum.map_reduce(effects, true, fn effect, resolved ->
        case Effect.init(id, effect) do
          {:resolve, _} = result ->
            {result, resolved}

          result ->
            {result, false}
        end
      end)

    if resolved do
      result = Enum.map(state, fn {:resolve, value} -> value end)
      {:resolve, result}
    else
      state
    end
  end

  @impl true
  def handle_event(id, event, _, state) do
    {state, {resolved, consumed}} =
      Enum.map_reduce(state, {true, false}, fn effect, {resolved, consumed} ->
        result =
          case effect do
            {:resolve, value} ->
              {:already_resolved, value}

            {effect, state} ->
              {effect, Effect.handle_event(id, event, effect, state)}
          end

        case result do
          {:already_resolved, value} ->
            {{:resolve, value}, {resolved, consumed}}

          {_effect, {:resolve, value}} ->
            {{:resolve, value}, {resolved, true}}

          {effect, {:consume, state}} ->
            {{effect, state}, {false, true}}

          {effect, state} ->
            {{effect, state}, {false, consumed}}
        end
      end)

    format_handled(state, resolved, consumed)
  end

  defp format_handled(state, resolved, consumed) do
    case {resolved, consumed} do
      {true, _} ->
        result = Enum.map(state, fn {:resolve, value} -> value end)
        {:resolve, result}

      {false, true} ->
        {:consume, state}

      {false, false} ->
        state
    end
  end
end
