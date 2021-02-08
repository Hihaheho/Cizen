defmodule Cizen.Effects.Dispatch do
  @moduledoc """
  An effect to dispatch an event.

  Returns the dispatched event.

  ## Example
        event = perform id, %Dispatch{
          body: some_event_body
        }
  """

  @keys [:body]
  @enforce_keys @keys
  defstruct @keys

  alias Cizen.Dispatcher
  alias Cizen.Effect

  use Effect

  @impl true
  def init(_, %__MODULE__{body: event}) do
    Dispatcher.dispatch(event)
    {:resolve, event}
  end

  @impl true
  def handle_event(_, _, _, _), do: nil
end
