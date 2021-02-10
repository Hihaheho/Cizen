defmodule Cizen.Effects.SubscribeTest do
  use Cizen.SagaCase

  alias Cizen.Automaton
  alias Cizen.Dispatcher
  alias Cizen.Effects.{Receive, Subscribe}
  alias Cizen.Filter
  alias Cizen.Saga
  alias Cizen.SagaID

  defmodule(TestEvent, do: defstruct([:value]))

  describe "Subscribe" do
    defmodule TestAutomaton do
      use Automaton

      defstruct [:pid]

      @impl true
      def yield(%__MODULE__{pid: pid}) do
        send(
          pid,
          perform(%Subscribe{
            event_filter: Filter.new(fn %TestEvent{} -> true end)
          })
        )

        send(
          pid,
          perform(%Receive{
            event_filter: Filter.new(fn %TestEvent{} -> true end)
          })
        )

        Automaton.finish()
      end
    end

    test "subscribes messages" do
      saga_id = SagaID.new()

      Saga.start_saga(saga_id, %TestAutomaton{pid: self()})

      assert_receive :ok
      event = %TestEvent{value: :a}
      Dispatcher.dispatch(event)
      assert_receive ^event
    end
  end
end
