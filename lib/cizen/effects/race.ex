defmodule Cizen.Effects.Race do
  @moduledoc """
  An effect to run a race for the given effects.

  ## Anonymous race
      perform %Race{
        effects: [
          effect1,
          effect2
        ]
      }
      # If effect2 resolves faster than effect1 with :somevalue,
      # the race returns the :somevalue

  ## Named Race
      perform %Race{
        effects: [
          effect1: effect1,
          effect2: effect2
        ]
      }
      # If effect2 resolves faster than effect1 with :somevalue,
      # the race returns the {effect2: :somevalue}
  """

  @keys [:effects]
  @enforce_keys @keys
  defstruct @keys

  alias Cizen.Effect
  alias Cizen.Effects.Map

  use Effect

  @impl true
  def init(id, %__MODULE__{effects: effects}) do
    effects =
      Enum.map(effects, fn
        {name, effect} ->
          %Map{
            effect: effect,
            transform: fn value -> {name, value} end
          }

        effect ->
          effect
      end)

    do_init(id, effects)
  end

  defp do_init(_id, []), do: []

  defp do_init(id, [effect | tail]) do
    case Effect.init(id, effect) do
      {:resolve, value} ->
        {:resolve, value}

      state ->
        case do_init(id, tail) do
          {:resolve, value} ->
            {:resolve, value}

          states ->
            [state | states]
        end
    end
  end

  @impl true
  def handle_event(id, event, _, state) do
    do_handle_event(id, event, state)
  end

  defp do_handle_event(_id, _event, []), do: []

  defp do_handle_event(id, event, [{effect, state} | tail]) do
    case Effect.handle_event(id, event, effect, state) do
      {:resolve, value} ->
        {:resolve, value}

      {:consume, state} ->
        do_handle_event_tail(effect, state, id, event, tail, true)

      state ->
        do_handle_event_tail(effect, state, id, event, tail, false)
    end
  end

  defp do_handle_event_tail(effect, state, id, event, tail, consumed) do
    case do_handle_event(id, event, tail) do
      {:resolve, value} ->
        {:resolve, value}

      {:consume, states} ->
        {:consume, [{effect, state} | states]}

      states ->
        if consumed do
          {:consume, [{effect, state} | states]}
        else
          [{effect, state} | states]
        end
    end
  end
end
