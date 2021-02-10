defmodule Cizen.Effects.RaceTest do
  use Cizen.SagaCase
  alias Cizen.EffectTestHelper.{TestEffect, TestEvent}

  alias Cizen.Automaton
  alias Cizen.Effect
  alias Cizen.Effects.{Dispatch, Race, Start, Subscribe}
  alias Cizen.Filter
  alias Cizen.SagaID

  describe "Race" do
    test "resolves immediately" do
      id = SagaID.new()

      effect = %Race{
        effects: [
          %TestEffect{value: :a},
          %TestEffect{value: :b, resolve_immediately: true}
        ]
      }

      assert {:resolve, :b} = Effect.init(id, effect)
    end

    test "does not resolve immediately if all effects do not resolve immediately" do
      id = SagaID.new()

      effect = %Race{
        effects: [
          %TestEffect{value: :a},
          %TestEffect{value: :b}
        ]
      }

      refute match?({:resolve, _}, Effect.init(id, effect))
    end

    test "consumes when the event is consumed" do
      id = SagaID.new()

      effect = %Race{
        effects: [
          %TestEffect{value: :a, ignores: [:c]},
          %TestEffect{value: :b}
        ]
      }

      {_, state} = Effect.init(id, effect)
      event = %TestEvent{value: :c}
      assert match?({:consume, _}, Effect.handle_event(id, event, effect, state))
    end

    test "ignores when the event is not consumed" do
      id = SagaID.new()

      effect = %Race{
        effects: [
          %TestEffect{value: :a},
          %TestEffect{value: :b}
        ]
      }

      {_, state} = Effect.init(id, effect)
      event = %TestEvent{value: :ignored}
      state = Effect.handle_event(id, event, effect, state)
      refute match?({:resolve, _}, state)
      refute match?({:consume, _}, state)
    end

    test "resolves when one resolve" do
      id = SagaID.new()

      effect = %Race{
        effects: [
          %TestEffect{value: :a},
          %TestEffect{value: :b},
          %TestEffect{value: :c, ignores: [:d]}
        ]
      }

      {_, state} = Effect.init(id, effect)
      event = %TestEvent{value: :d}
      {:consume, state} = Effect.handle_event(id, event, effect, state)
      event = %TestEvent{value: :b}
      assert {:resolve, :b} == Effect.handle_event(id, event, effect, state)
    end

    test "works with aliases" do
      id = SagaID.new()

      effect = %Race{
        effects: [
          %TestEffect{
            value: :a,
            alias_of: %TestEffect{value: :d}
          },
          %TestEffect{
            value: :b,
            alias_of: %TestEffect{value: :e}
          },
          %TestEffect{
            value: :c,
            alias_of: %TestEffect{value: :f, ignores: [:c]}
          }
        ]
      }

      {_, state} = Effect.init(id, effect)
      event = %TestEvent{value: :c}
      {:consume, state} = Effect.handle_event(id, event, effect, state)
      event = %TestEvent{value: :e}
      assert {:resolve, :e} == Effect.handle_event(id, event, effect, state)
    end

    test "allows named effects" do
      id = SagaID.new()

      effect = %Race{
        effects: [
          effect_a: %TestEffect{value: :a},
          effect_b: %TestEffect{value: :b},
          effect_c: %TestEffect{value: :c, ignores: [:d]}
        ]
      }

      {_, state} = Effect.init(id, effect)
      event = %TestEvent{value: :d}
      {:consume, state} = Effect.handle_event(id, event, effect, state)
      event = %TestEvent{value: :b}
      assert {:resolve, {:effect_b, :b}} == Effect.handle_event(id, event, effect, state)
    end

    defmodule TestAutomaton do
      use Automaton

      defstruct [:pid]

      @impl true
      def spawn(struct) do
        perform(%Subscribe{
          event_filter: Filter.new(fn %TestEvent{} -> true end)
        })

        struct
      end

      @impl true
      def yield(%__MODULE__{pid: pid}) do
        send(
          pid,
          perform(%Race{
            effects: [
              effect1: %TestEffect{value: :a},
              effect2: %TestEffect{value: :b},
              effect3: %TestEffect{value: :d, alias_of: %TestEffect{value: :c, ignores: [:d]}}
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
            value: :d
          }
        })

        perform(%Dispatch{
          body: %TestEvent{
            value: :b
          }
        })

        assert_receive {:effect2, :b}
      end)
    end
  end
end
