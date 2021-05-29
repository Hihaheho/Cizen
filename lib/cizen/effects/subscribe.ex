defmodule Cizen.Effects.Subscribe do
  @moduledoc """
  An effect to subscribe messages.

  Returns :ok.

  ## Example
      perform %Subscribe{
        event_filter: Pattern.new(fn %SomeEvent{} -> true end)
      }
  """

  @enforce_keys [:event_filter]
  defstruct [:event_filter]

  alias Cizen.Dispatcher
  alias Cizen.Effect

  use Effect

  @impl true
  def init(handler, %__MODULE__{event_filter: event_filter}) do
    Dispatcher.listen(handler, event_filter)
    {:resolve, :ok}
  end

  @impl true
  def handle_event(_, _, _, _), do: nil
end
