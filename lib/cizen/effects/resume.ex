defmodule Cizen.Effects.Resume do
  @moduledoc """
  An effect to resume a saga.

  Returns the resumed saga ID.

  ## Example
      ^some_saga_id = perform %Resume{
        id: some_saga_id,
        saga: some_saga_struct,
        state: some_saga_state,
      }
  """

  @enforce_keys [:id, :saga, :state]
  defstruct @enforce_keys

  alias Cizen.Dispatcher
  alias Cizen.Effect
  alias Cizen.Pattern
  alias Cizen.Saga

  use Effect
  require Pattern

  @impl true
  def init(_, %__MODULE__{id: saga_id, saga: saga, state: state}) do
    Task.async(fn ->
      Dispatcher.listen(Pattern.new(fn %Saga.Resumed{saga_id: ^saga_id} -> true end))
      Saga.resume(saga_id, saga, state)

      receive do
        %Saga.Resumed{saga_id: ^saga_id} -> :ok
      end
    end)
    |> Task.await()

    {:resolve, saga_id}
  end

  @impl true
  def handle_event(_, _, _, _), do: nil
end
