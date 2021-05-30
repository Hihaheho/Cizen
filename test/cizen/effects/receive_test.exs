defmodule Cizen.Effects.ReceiveTest do
  use Cizen.SagaCase

  alias Cizen.Automaton
  alias Cizen.Dispatcher
  alias Cizen.Effect
  alias Cizen.Effects.Receive
  alias Cizen.Pattern
  alias Cizen.Saga
  alias Cizen.SagaID

  defmodule(TestEvent1, do: defstruct([:value]))
  defmodule(TestEvent2, do: defstruct([:value]))

  defp setup_receive(_context) do
    id = SagaID.new()

    effect = %Receive{
      pattern: Pattern.new(fn %TestEvent1{} -> true end)
    }

    %{handler: id, effect: effect}
  end

  describe "Receive" do
    setup [:setup_receive]

    test "does not resolves on init", %{handler: id, effect: effect} do
      refute match?({:resolve, _}, Effect.init(id, effect))
    end

    test "resolves if matched", %{handler: id, effect: effect} do
      {_, state} = Effect.init(id, effect)

      event = %TestEvent1{}
      assert {:resolve, ^event} = Effect.handle_event(id, event, effect, state)
    end

    test "does not resolve or consume if not matched", %{handler: id, effect: effect} do
      {_, state} = Effect.init(id, effect)

      next = Effect.handle_event(id, %TestEvent2{}, effect, state)

      refute match?(
               {:resolve, _},
               next
             )

      refute match?(
               {:consume, _},
               next
             )
    end

    test "uses the default event filter" do
      assert %Receive{} == %Receive{pattern: %Pattern{}}
    end

    defmodule TestAutomaton do
      use Automaton

      defstruct [:pid]

      @impl true
      def yield(%__MODULE__{pid: pid}) do
        test_event1_filter = Pattern.new(fn %TestEvent1{} -> true end)
        test_event2_filter = Pattern.new(fn %TestEvent2{} -> true end)

        id = Saga.self()
        Dispatcher.listen(id, test_event1_filter)
        Dispatcher.listen(id, test_event2_filter)

        send(pid, :launched)

        send(pid, perform(%Receive{pattern: test_event1_filter}))
        send(pid, perform(%Receive{pattern: test_event2_filter}))

        Automaton.finish()
      end
    end

    test "works with Automaton" do
      saga_id = SagaID.new()
      Dispatcher.listen(Pattern.new(fn %Saga.Finish{saga_id: ^saga_id} -> true end))

      Saga.start(%TestAutomaton{pid: self()}, saga_id: saga_id)

      assert_receive :launched

      event1 = %TestEvent1{value: 1}
      Dispatcher.dispatch(event1)

      assert_receive ^event1

      event2 = %TestEvent2{value: 2}
      Dispatcher.dispatch(event2)

      assert_receive ^event2

      assert_receive %Saga.Finish{saga_id: ^saga_id}
    end
  end
end
