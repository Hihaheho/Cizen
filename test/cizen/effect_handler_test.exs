defmodule Cizen.EventHandlerTest do
  use ExUnit.Case
  alias Cizen.EffectHandlerTestHelper.{TestEffect, TestEvent}

  alias Cizen.EffectHandler
  alias Cizen.SagaID

  describe "init/3" do
    test "starts effect producer" do
      saga_id = SagaID.new()
      state = EffectHandler.init(saga_id)
      assert state == %{handler: saga_id, effect: nil, effect_state: nil, event_buffer: []}
    end
  end

  defp setup_handler(_context) do
    saga_id = SagaID.new()
    handler = EffectHandler.init(saga_id)
    %{handler: handler}
  end

  defp do_perform(state, effect) do
    EffectHandler.perform_effect(state, effect)
  end

  defp do_feed(state, body) do
    EffectHandler.feed_event(state, body)
  end

  describe "feed_event/3" do
    setup [:setup_handler]

    test "resolves immediately", %{handler: state} do
      result =
        state
        |> do_perform(%TestEffect{resolve_immediately: true, value: :a})

      assert {:resolve, {:a, 0}, %{effect: nil, event_buffer: []}} = result
    end

    test "resolves on event which will come after PerformEffect event", %{handler: state} do
      result =
        state
        |> do_perform(%TestEffect{value: :a})
        |> do_feed(%TestEvent{value: :a, count: 1})

      assert {:resolve, {:a, 1}, %{effect: nil, event_buffer: []}} = result
    end

    test "resolves on event which came before PerformEffect event", %{handler: state} do
      result =
        state
        |> do_feed(%TestEvent{value: :a, count: 1})
        |> do_perform(%TestEffect{value: :a})

      assert {:resolve, {:a, 1}, %{effect: nil, event_buffer: []}} = result
    end

    test "feeds events from the buffer", %{handler: state} do
      result =
        state
        |> do_feed(%TestEvent{value: :a, count: 3})
        |> do_feed(%TestEvent{value: :a, count: 3})
        |> do_feed(%TestEvent{value: :a, count: 3})
        |> do_perform(%TestEffect{value: :a})

      assert {:resolve, {:a, 3}, %{effect: nil, event_buffer: []}} = result
    end

    test "does not resolve for unmatched events", %{handler: state} do
      effect = %TestEffect{value: :a}
      event_2 = %TestEvent{value: :b, count: 2}

      state =
        state
        |> do_perform(effect)
        |> do_feed(%TestEvent{value: :a, count: 2})
        |> do_feed(event_2)

      assert state.effect == %TestEffect{value: :a}
      assert Enum.map(state.event_buffer, & &1) == [event_2]
    end

    test "keep only not consumed events in the buffer", %{handler: state} do
      effect = %TestEffect{value: :a}
      event_1 = %TestEvent{value: :b, count: 1}
      event_2 = %TestEvent{value: :b, count: 2}

      {:resolve, {:a, 3}, state} =
        state
        |> do_feed(event_1)
        |> do_feed(%TestEvent{value: :a, count: 3})
        |> do_perform(effect)
        |> do_feed(event_2)
        |> do_feed(%TestEvent{value: :a, count: 3})
        |> do_feed(%TestEvent{value: :a, count: 3})

      assert Enum.map(state.event_buffer, & &1) == [event_1, event_2]
    end

    test "keep not consumed events in the buffer after resolve", %{handler: state} do
      effect = %TestEffect{value: :a}
      event_1 = %TestEvent{value: :b, count: 1}
      event_2 = %TestEvent{value: :b, count: 2}

      {:resolve, {:a, 1}, state} =
        state
        |> do_feed(event_1)
        |> do_feed(%TestEvent{value: :a, count: 1})
        |> do_feed(event_2)
        |> do_perform(effect)

      assert Enum.map(state.event_buffer, & &1) == [event_1, event_2]
    end

    test "update the effect state", %{handler: initial_state} do
      state =
        initial_state
        |> do_feed(%TestEvent{value: :a, count: 2})
        |> do_perform(%TestEffect{reset: true, value: :a})

      assert state.effect_state == 1

      state =
        initial_state
        |> do_feed(%TestEvent{value: :a, count: 2})
        |> do_feed(%TestEvent{value: :b, count: 1})
        |> do_perform(%TestEffect{reset: true, value: :a})

      assert state.effect_state == 0

      state =
        initial_state
        |> do_feed(%TestEvent{value: :a, count: 3})
        |> do_perform(%TestEffect{reset: true, value: :a})
        |> do_feed(%TestEvent{value: :a, count: 3})

      assert state.effect_state == 2

      state =
        initial_state
        |> do_feed(%TestEvent{value: :a, count: 3})
        |> do_perform(%TestEffect{reset: true, value: :a})
        |> do_feed(%TestEvent{value: :a, count: 3})
        |> do_feed(%TestEvent{value: :b, count: 1})

      assert state.effect_state == 0
    end

    test "resolves immediately with using alias", %{handler: state} do
      result =
        state
        |> do_perform(%TestEffect{
          value: :b,
          alias_of: %TestEffect{resolve_immediately: true, value: :a}
        })

      assert {:resolve, {:a, 0}, %{effect: nil, event_buffer: []}} = result
    end

    test "resolves with using alias", %{handler: state} do
      result =
        state
        |> do_feed(%TestEvent{value: :b, count: 2})
        |> do_perform(%TestEffect{
          value: :a,
          alias_of: %TestEffect{value: :b}
        })
        |> do_feed(%TestEvent{value: :b, count: 2})

      assert {:resolve, {:b, 2}, %{effect: nil, event_buffer: []}} = result
    end
  end
end
