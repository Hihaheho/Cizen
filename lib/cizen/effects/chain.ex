defmodule Cizen.Effects.Chain do
  @moduledoc """
  An effect to chain multiple effects.

  Returns the list of resolved values.
  If an element of the effects list is a function,
  it called with results of resolved effects,
  and its result is treated as the next effect.

  ## Example
        [result1, result2, result3, result4] = perform %Chain{
          effects: [
            effect1,
            effect2,
            fn result1, result2 -> effect3 end,
            effect4
          ]
        }
  """

  @keys [:effects]
  @enforce_keys @keys
  defstruct @keys

  alias Cizen.Effect

  use Effect

  @impl true
  def init(id, %__MODULE__{effects: effects}) do
    {values, effects, effect_state} = do_init(id, effects)

    if effects == [] do
      {:resolve, Enum.reverse(values)}
    else
      {values, effects, effect_state}
    end
  end

  @impl true
  def handle_event(id, event, _, {values, [effect | tail] = effects, effect_state}) do
    case Effect.handle_event(id, event, effect, effect_state) do
      {:resolve, value} ->
        if tail == [] do
          {:resolve, Enum.reverse([value | values])}
        else
          {values, effects, effect_state} = do_init(id, tail, [value | values])

          if effects == [] do
            {:resolve, Enum.reverse(values)}
          else
            {:consume, {values, effects, effect_state}}
          end
        end

      {:consume, state} ->
        {:consume, {values, effects, state}}

      state ->
        {values, effects, state}
    end
  end

  defp do_init(id, effects, values \\ [])
  defp do_init(_id, [], values), do: {values, [], nil}

  defp do_init(id, [effect | tail], values) do
    effect =
      if is_function(effect) do
        apply(effect, Enum.reverse(values))
      else
        effect
      end

    case Effect.init(id, effect) do
      {:resolve, value} ->
        do_init(id, tail, [value | values])

      {effect, state} ->
        {values, [effect | tail], state}
    end
  end
end
