defmodule Cizen.TestTest do
  use ExUnit.Case
  use Cizen.Test
  alias Cizen.TestHelper
  import Cizen.TestHelper, only: [assert_condition: 2]
  import ExUnit.Callbacks, only: [setup_all: 1, on_exit: 1]

  use Cizen.Effects
  alias Cizen.{Dispatcher, Filter}
  alias Cizen.SagaRegistry

  defmodule TestEvent do
    defstruct [:value]
  end

  defmodule TestSaga do
    use Cizen.Automaton

    def yield(_) do
      # Block infinitely
      perform %Receive{}
    end
  end

  setup_all do
    {:ok, pid} = SagaRegistry.start_link(keys: :duplicate, name: TestSagaRegistry)

    on_exit(fn ->
      assert_condition(10, 0 == SagaRegistry.count(TestSagaRegistry))
      Process.exit(pid, :kill)
    end)
  end

  test "assert_handle" do
    result =
      assert_handle(fn ->
        perform(%Subscribe{
          event_filter: Filter.new(fn %TestEvent{} -> true end)
        })

        Dispatcher.dispatch(%TestEvent{value: 1})
        event = perform %Receive{}
        event.value + 1
      end)

    assert 2 == result
  end

  test "assert_handle with timeout" do
    result =
      assert_handle(15, fn ->
        perform(%Subscribe{
          event_filter: Filter.new(fn %TestEvent{} -> true end)
        })

        Dispatcher.dispatch(%TestEvent{value: 1})
        event = perform %Receive{}
        event.value + 1
      end)

    assert 2 == result
  end

  test "assert_handle fails with timeout" do
    assert_raise ExUnit.AssertionError, fn ->
      assert_handle(10, fn ->
        perform %Receive{}
      end)
    end
  end

  test "assert_perform" do
    result =
      assert_handle(fn ->
        perform(%Subscribe{
          event_filter: Filter.new(fn %TestEvent{} -> true end)
        })

        Dispatcher.dispatch(%TestEvent{value: 1})
        event = assert_perform(%Receive{})
        event.value + 1
      end)

    assert 2 == result
  end

  test "assert_perform with timeout" do
    result =
      assert_handle(fn ->
        perform(%Subscribe{
          event_filter: Filter.new(fn %TestEvent{} -> true end)
        })

        Dispatcher.dispatch(%TestEvent{value: 1})
        event = assert_perform(10, %Receive{})
        event.value + 1
      end)

    assert 2 == result
  end

  test "assert_perform fails with timeout" do
    handle fn ->
      assert_raise ExUnit.AssertionError, fn ->
        assert_perform(10, %Receive{})
      end
    end
  end

  test "finish started sagas" do
    a = TestHelper.launch_test_saga()
    b = TestHelper.launch_test_saga()
    c = TestHelper.launch_test_saga()
    SagaRegistry.register(TestSagaRegistry, a, :key, :value)
    SagaRegistry.register(TestSagaRegistry, b, :key, :value)
    SagaRegistry.register(TestSagaRegistry, c, :key, :value)
  end
end
