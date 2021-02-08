defmodule Cizen.EffectHandler do
  @moduledoc """
  Handles effects.
  """

  alias Cizen.Effect
  alias Cizen.Event
  alias Cizen.SagaID

  @type state :: %{
          handler: SagaID.t(),
          effect: Effect.t() | nil,
          effect_state: term,
          event_buffer: list(Event.t())
        }
  @type resolve :: {:resolve, term, state}

  @spec init(SagaID.t()) :: state
  def init(handler) do
    %{handler: handler, effect: nil, effect_state: nil, event_buffer: []}
  end

  @spec perform_effect(state, Effect.t()) :: resolve | state
  def perform_effect(state, effect) do
    case Effect.init(state.handler, effect) do
      {:resolve, value} ->
        {:resolve, value, state}

      {effect, effect_state} ->
        state = %{state | effect: effect, effect_state: effect_state}

        case feed_events(state, state.event_buffer) do
          {:resolve, value, state, events} ->
            {:resolve, value, %{state | event_buffer: events}}

          {state, events} ->
            %{state | event_buffer: events}
        end
    end
  end

  @spec feed_event(state, Event.t()) :: resolve | state
  def feed_event(state, event) do
    case state do
      %{effect: nil} ->
        append_to_buffer(state, event)

      state ->
        {resolved, value, state, events} =
          case feed_events(state, [event]) do
            {:resolve, value, state, events} -> {true, value, state, events}
            {state, events} -> {false, nil, state, events}
          end

        # length must be 0 or 1
        state =
          if events == [] do
            state
          else
            append_to_buffer(state, event)
          end

        if resolved do
          {:resolve, value, state}
        else
          state
        end
    end
  end

  defp append_to_buffer(state, event) do
    event_buffer = state.event_buffer ++ [event]
    %{state | event_buffer: event_buffer}
  end

  defp feed_events(state, []), do: {state, []}

  defp feed_events(state, [event | tail]) do
    case Effect.handle_event(state.handler, event, state.effect, state.effect_state) do
      {:resolve, value} ->
        state = %{state | effect: nil}
        {:resolve, value, state, tail}

      {:consume, effect_state} ->
        state = %{state | effect_state: effect_state}
        feed_events(state, tail)

      effect_state ->
        state = %{state | effect_state: effect_state}

        {resolved, value, state, tail} =
          case feed_events(state, tail) do
            {:resolve, value, state, events} -> {true, value, state, events}
            {state, events} -> {false, nil, state, events}
          end

        tail = [event | tail]

        if resolved do
          {:resolve, value, state, tail}
        else
          {state, tail}
        end
    end
  end
end
