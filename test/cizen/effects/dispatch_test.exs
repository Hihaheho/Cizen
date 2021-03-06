defmodule Cizen.Effects.DispatchTest do
  use Cizen.SagaCase
  alias Cizen.TestHelper

  alias Cizen.Automaton
  alias Cizen.Dispatcher
  alias Cizen.Effect
  alias Cizen.Effects.Dispatch
  alias Cizen.Pattern
  alias Cizen.Saga
  alias Cizen.SagaID

  require Pattern

  defmodule(TestEvent, do: defstruct([:value]))

  defp setup_dispatch(_context) do
    id = TestHelper.launch_test_saga()

    effect = %Dispatch{
      body: %TestEvent{value: :a}
    }

    %{handler: id, effect: effect, body: %TestEvent{value: :a}}
  end

  describe "Dispatch" do
    setup [:setup_dispatch]

    test "resolves and dispatches an event on init", %{handler: id, effect: effect, body: body} do
      Dispatcher.listen_event_type(TestEvent)
      assert {:resolve, ^body} = Effect.init(id, effect)
      assert_receive ^body
    end

    defmodule TestAutomaton do
      use Automaton

      defstruct [:pid]

      @impl true
      def yield(%__MODULE__{pid: pid}) do
        send(pid, perform(%Dispatch{body: %TestEvent{value: :a}}))
        send(pid, perform(%Dispatch{body: %TestEvent{value: :b}}))

        Automaton.finish()
      end
    end

    test "works with Automaton" do
      saga_id = SagaID.new()
      Dispatcher.listen_event_type(TestEvent)
      Dispatcher.listen(Pattern.new(fn %Saga.Finish{saga_id: ^saga_id} -> true end))

      Saga.start(%TestAutomaton{pid: self()}, saga_id: saga_id)

      event_a = assert_receive %TestEvent{value: :a}
      assert_receive ^event_a

      event_b = assert_receive %TestEvent{value: :b}
      assert_receive ^event_b

      assert_receive %Saga.Finish{saga_id: ^saga_id}
    end
  end
end
