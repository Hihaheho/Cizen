defmodule Cizen.Effects.AllTest do
  use Cizen.SagaCase
  alias Cizen.EffectTestHelper.{TestEffect, TestEvent}

  alias Cizen.Automaton
  alias Cizen.Effect
  alias Cizen.Effects.{All, Dispatch, Start, Subscribe}
  alias Cizen.Pattern
  alias Cizen.SagaID

  describe "All" do
    test "resolves immediately with no effects" do
      id = SagaID.new()

      effect = %All{
        effects: []
      }

      assert {:resolve, []} = Effect.init(id, effect)
    end

    test "resolves immediately if effects resolve immediately" do
      id = SagaID.new()

      effect = %All{
        effects: [
          %TestEffect{value: :a, resolve_immediately: true},
          %TestEffect{value: :b, resolve_immediately: true}
        ]
      }

      assert {:resolve, [:a, :b]} = Effect.init(id, effect)
    end

    test "does not resolve immediately if one or more effects do not resolve immediately" do
      id = SagaID.new()

      effect = %All{
        effects: [
          %TestEffect{value: :a, resolve_immediately: true},
          %TestEffect{value: :b}
        ]
      }

      refute match?({:resolve, _}, Effect.init(id, effect))
    end

    test "consumes when the event is consumed" do
      id = SagaID.new()

      effect = %All{
        effects: [
          %TestEffect{value: :a, resolve_immediately: true},
          %TestEffect{value: :b},
          %TestEffect{value: :c, ignores: [:b]}
        ]
      }

      {_, state} = Effect.init(id, effect)
      event = %TestEvent{value: :b}
      assert match?({:consume, _}, Effect.handle_event(id, event, effect, state))
    end

    test "ignores when the event is not consumed" do
      id = SagaID.new()

      effect = %All{
        effects: [
          %TestEffect{value: :a, resolve_immediately: true},
          %TestEffect{value: :b}
        ]
      }

      {_, state} = Effect.init(id, effect)
      event = %TestEvent{value: :ignored}
      state = Effect.handle_event(id, event, effect, state)
      refute match?({:resolve, _}, state)
      refute match?({:consume, _}, state)
    end

    test "resolves when all effects resolve" do
      id = SagaID.new()

      effect = %All{
        effects: [
          %TestEffect{value: :a, resolve_immediately: true},
          %TestEffect{value: :b},
          %TestEffect{value: :c, ignores: [:b]}
        ]
      }

      {_, state} = Effect.init(id, effect)
      event = %TestEvent{value: :b}
      {:consume, state} = Effect.handle_event(id, event, effect, state)
      event = %TestEvent{value: :c}
      assert {:resolve, [:a, :b, :c]} == Effect.handle_event(id, event, effect, state)
    end

    test "works with aliases" do
      id = SagaID.new()

      effect = %All{
        effects: [
          %TestEffect{
            value: :a,
            alias_of: %TestEffect{value: :b, resolve_immediately: true}
          },
          %TestEffect{
            value: :b,
            alias_of: %TestEffect{value: :c}
          },
          %TestEffect{
            value: :c,
            alias_of: %TestEffect{value: :d, ignores: [:c]}
          }
        ]
      }

      {_, state} = Effect.init(id, effect)
      event = %TestEvent{value: :c}
      {:consume, state} = Effect.handle_event(id, event, effect, state)
      event = %TestEvent{value: :d}
      assert {:resolve, [:b, :c, :d]} == Effect.handle_event(id, event, effect, state)
    end

    defmodule TestAutomaton do
      use Automaton

      defstruct [:pid]

      @impl true
      def spawn(struct) do
        perform(%Subscribe{
          pattern: Pattern.new(fn %TestEvent{} -> true end)
        })

        struct
      end

      @impl true
      def yield(%__MODULE__{pid: pid}) do
        send(
          pid,
          perform(%All{
            effects: [
              %TestEffect{value: :a, resolve_immediately: true},
              %TestEffect{value: :b},
              %TestEffect{value: :c, alias_of: %TestEffect{value: :d, ignores: [:b]}}
            ]
          })
        )

        Automaton.finish()
      end
    end

    test "works with perform" do
      assert_handle(fn ->
        perform(%Start{
          saga: %TestAutomaton{pid: self()}
        })

        perform(%Dispatch{
          body: %TestEvent{
            value: :b
          }
        })

        perform(%Dispatch{
          body: %TestEvent{
            value: :d
          }
        })

        assert_receive [:a, :b, :d]
      end)
    end
  end
end
