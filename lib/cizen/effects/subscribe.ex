defmodule Cizen.Effects.Subscribe do
  @moduledoc """
  An effect to subscribe messages.

  Returns :ok.

  ## Example
      perform %Subscribe{
        pattern: Pattern.new(fn %SomeEvent{} -> true end)
      }
  """

  @enforce_keys [:pattern]
  defstruct [:pattern]

  alias Cizen.Dispatcher
  alias Cizen.Effect

  use Effect

  @impl true
  def init(handler, %__MODULE__{pattern: pattern}) do
    Dispatcher.listen(handler, pattern)
    {:resolve, :ok}
  end

  @impl true
  def handle_event(_, _, _, _), do: nil
end
