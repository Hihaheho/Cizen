defmodule Cizen.DispatcherTest do
  use Cizen.SagaCase
  alias Cizen.TestHelper

  alias Cizen.Dispatcher
  alias Cizen.Pattern
  alias Cizen.SagaID
  require Cizen.Pattern

  defmodule(TestEvent, do: defstruct([:value]))

  defp wait_until_receive(message) do
    receive do
      ^message -> :ok
    after
      100 -> flunk("#{message} timeout")
    end
  end

  test "listen_all" do
    pid = self()

    task1 =
      Task.async(fn ->
        Dispatcher.listen_all()
        send(pid, :task1)
        assert_receive %TestEvent{value: :a}
        assert_receive %TestEvent{value: :b}
      end)

    task2 =
      Task.async(fn ->
        Dispatcher.listen_all()
        send(pid, :task2)
        assert_receive %TestEvent{value: :a}
        assert_receive %TestEvent{value: :b}
      end)

    wait_until_receive(:task1)
    wait_until_receive(:task2)
    Dispatcher.dispatch(%TestEvent{value: :a})
    Dispatcher.dispatch(%TestEvent{value: :b})
    Task.await(task1)
    Task.await(task2)
  end

  defmodule(TestEventA, do: defstruct([:value]))
  defmodule(TestEventB, do: defstruct([:value]))

  test "listen_event_type" do
    pid = self()

    task1 =
      Task.async(fn ->
        Dispatcher.listen_event_type(TestEventA)
        send(pid, :task1)
        assert_receive %TestEventA{value: :a}
        refute_receive %TestEventB{value: :b}
      end)

    task2 =
      Task.async(fn ->
        Dispatcher.listen_event_type(TestEventA)
        Dispatcher.listen_event_type(TestEventB)
        send(pid, :task2)
        assert_receive %TestEventA{value: :a}
        assert_receive %TestEventB{value: :b}
      end)

    wait_until_receive(:task1)
    wait_until_receive(:task2)
    Dispatcher.dispatch(%TestEventA{value: :a})
    Dispatcher.dispatch(%TestEventB{value: :b})
    Task.await(task1)
    Task.await(task2)
  end

  test "listen" do
    pid = self()

    task1 =
      Task.async(fn ->
        Dispatcher.listen(Pattern.new(fn %TestEventA{} -> true end))
        send(pid, :task1)
        assert_receive %TestEventA{}
        refute_receive %TestEventB{}
      end)

    task2 =
      Task.async(fn ->
        Dispatcher.listen(Pattern.new(fn %TestEventA{} -> true end))
        Dispatcher.listen(Pattern.new(fn %TestEventB{} -> true end))
        send(pid, :task2)
        assert_receive %TestEventA{}
        assert_receive %TestEventB{}
      end)

    wait_until_receive(:task1)
    wait_until_receive(:task2)
    Dispatcher.dispatch(%TestEventA{})
    Dispatcher.dispatch(%TestEventB{})
    Task.await(task1)
    Task.await(task2)
  end

  test "listen with saga ID" do
    pid = self()

    saga_id =
      TestHelper.launch_test_saga(
        handle_event: fn event, _state ->
          case event do
            %TestEventA{} ->
              send(pid, :received)
          end
        end
      )

    Dispatcher.listen(saga_id, Pattern.new(fn %TestEventA{} -> true end))

    Dispatcher.dispatch(%TestEventA{})

    wait_until_receive(:received)
  end

  test "listen with saga ID which not alive" do
    saga_id = SagaID.new()

    assert :ok ==
             Dispatcher.listen(saga_id, Pattern.new(fn %TestEventA{} -> true end))
  end
end
