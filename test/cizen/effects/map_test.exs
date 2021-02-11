defmodule Cizen.Effects.MapTest do
  use Cizen.SagaCase
  alias Cizen.EffectTestHelper.{TestEffect, TestEvent}

  alias Cizen.Automaton
  alias Cizen.Dispatcher
  alias Cizen.Effect
  alias Cizen.Filter
  alias Cizen.Saga
  alias Cizen.SagaID

  require Filter

  use Cizen.Effects, only: [Map]

  describe "Map" do
    test "transform the result when the effect immediately resolves" do
      id = SagaID.new()

      effect = %Map{
        effect: %TestEffect{value: :a, resolve_immediately: true},
        transform: fn :a -> :transformed_a end
      }

      assert {:resolve, :transformed_a} == Effect.init(id, effect)
    end

    test "returns the state of the effect on init" do
      id = SagaID.new()

      effect = %Map{
        effect: %TestEffect{value: :a},
        transform: fn :a -> :transformed_a end
      }

      assert {effect, {effect.effect, :a}} == Effect.init(id, effect)
    end

    test "transforms the result when the effect resolves" do
      id = SagaID.new()

      effect = %Map{
        effect: %TestEffect{value: :a},
        transform: fn :a -> :transformed_a end
      }

      {effect, state} = Effect.init(id, effect)
      event = %TestEvent{value: :a}
      assert {:resolve, :transformed_a} == Effect.handle_event(id, event, effect, state)
    end

    test "consumes an event" do
      id = SagaID.new()

      effect = %Map{
        effect: %TestEffect{value: :a},
        transform: fn :a -> :transformed_a end
      }

      {effect, state} = Effect.init(id, effect)
      event = %TestEvent{value: :b}
      assert {:consume, {effect.effect, :a}} == Effect.handle_event(id, event, effect, state)
    end

    test "ignores an event" do
      id = SagaID.new()

      effect = %Map{
        effect: %TestEffect{value: :a},
        transform: fn :a -> :transformed_a end
      }

      {effect, state} = Effect.init(id, effect)
      event = %TestEvent{value: :ignored}
      assert {effect.effect, :a} == Effect.handle_event(id, event, effect, state)
    end

    test "works with alias" do
      id = SagaID.new()

      effect = %Map{
        effect: %TestEffect{value: :a, alias_of: %TestEffect{value: :b}},
        transform: fn
          :a -> :transformed_a
          :b -> :transformed_b
        end
      }

      {effect, state} = Effect.init(id, effect)
      assert {effect.effect.alias_of, :b} == state
      event = %TestEvent{value: :b}
      assert {:resolve, :transformed_b} == Effect.handle_event(id, event, effect, state)
    end

    defmodule TestAutomaton do
      use Automaton

      defstruct [:pid]

      @impl true
      def yield(%__MODULE__{pid: pid}) do
        Dispatcher.listen(Saga.self(), Filter.new(fn %TestEvent{} -> true end))

        send(pid, :launched)

        send(
          pid,
          perform(%Map{
            effect: %TestEffect{value: :a, resolve_immediately: true},
            transform: fn :a -> :transformed_a end
          })
        )

        send(
          pid,
          perform(%Map{
            effect: %TestEffect{value: :b},
            transform: fn :b -> :transformed_b end
          })
        )

        Automaton.finish()
      end
    end

    test "transforms the result" do
      saga_id = SagaID.new()
      Dispatcher.listen(Filter.new(fn %Saga.Finish{saga_id: ^saga_id} -> true end))

      Saga.start_link(%TestAutomaton{pid: self()}, saga_id: saga_id)

      assert_receive :launched

      assert_receive :transformed_a

      Dispatcher.dispatch(%TestEvent{
        value: :c
      })

      Dispatcher.dispatch(%TestEvent{
        value: :ignored
      })

      Dispatcher.dispatch(%TestEvent{
        value: :b
      })

      assert_receive :transformed_b

      assert_receive %Saga.Finish{saga_id: ^saga_id}
    end
  end
end
