defmodule Cizen.Effects.Receive do
  @moduledoc """
  An effect to receive an event which the saga is received.

  Returns the received event.

  If the `event_filter` is omitted, this receives all events.

  ## Example
      perform %Subscribe{
        event_filter: Pattern.new(fn %SomeEvent{} -> true end)
      }

      perform %Receive{
        event_filter: Pattern.new(fn %SomeEvent{} -> true end)
      }
  """

  alias Cizen.Effect
  alias Cizen.Pattern

  defstruct event_filter: %Pattern{}

  use Effect

  @impl true
  def init(_handler, %__MODULE__{}) do
    :ok
  end

  @impl true
  def handle_event(_handler, event, effect, state) do
    if Pattern.match?(effect.event_filter, event) do
      {:resolve, event}
    else
      state
    end
  end
end
