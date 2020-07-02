defmodule Cizen.Dispatcher.SenderTest do
  use ExUnit.Case, async: false

  import Mock

  alias Cizen.Dispatcher.{Sender, Node}
  alias Cizen.Event

  defmodule(TestEvent, do: defstruct([]))

  setup_with_mocks([
    {
      Node,
      [:passthrough],
      [init: fn _ -> {:ok, nil} end]
    }
  ]) do
    event = Event.new(nil, %TestEvent{})

    subscriber1 =
      spawn(fn ->
        receive do
          ^event -> :ok
        end
      end)

    subscriber2 =
      spawn(fn ->
        receive do
          ^event -> :ok
        end
      end)

    :erlang.trace(subscriber1, true, [:receive])
    :erlang.trace(subscriber2, true, [:receive])

    %{some_event: event, subscriber1: subscriber1, subscriber2: subscriber2}
  end

  test "sender sends event to subscribers", %{
    some_event: event,
    subscriber1: subscriber1,
    subscriber2: subscriber2
  } do
    {:ok, sender} = Sender.start_link(nil)
    {:ok, root_node} = Node.start_link()
    {:ok, leaf_node} = Node.start_link()
    Sender.wait_node(sender, root_node)
    Sender.put_event(sender, event)

    refute_receive {:trace, ^subscriber1, :receive, ^event}
    refute_receive {:trace, ^subscriber2, :receive, ^event}
    Sender.put_subscribers_and_following_nodes(sender, root_node, [subscriber1], [leaf_node])
    refute_receive {:trace, ^subscriber1, :receive, ^event}
    refute_receive {:trace, ^subscriber2, :receive, ^event}
    Sender.put_subscribers_and_following_nodes(sender, leaf_node, [subscriber2], [])
    assert_receive {:trace, ^subscriber1, :receive, ^event}
    assert_receive {:trace, ^subscriber2, :receive, ^event}
  end

  test "sender does not send event to subscribers if preceding sender is alive", %{
    some_event: event,
    subscriber1: subscriber
  } do
    {:ok, preceding} = Sender.start_link(nil)
    {:ok, sender} = Sender.start_link(preceding)
    {:ok, node} = Node.start_link()
    Sender.wait_node(sender, node)
    Sender.put_event(sender, event)

    Sender.put_subscribers_and_following_nodes(sender, node, [subscriber], [])
    refute_receive {:trace, ^subscriber, :receive, ^event}
    GenServer.stop(preceding)
    assert_receive {:trace, ^subscriber, :receive, ^event}
  end

  test "sender does not send event to subscribers if event is not given", %{
    some_event: event,
    subscriber1: subscriber
  } do
    {:ok, sender} = Sender.start_link(nil)
    {:ok, node} = Node.start_link()
    Sender.wait_node(sender, node)

    Sender.put_subscribers_and_following_nodes(sender, node, [subscriber], [])
    refute_receive {:trace, ^subscriber, :receive, ^event}
    Sender.put_event(sender, event)
    assert_receive {:trace, ^subscriber, :receive, ^event}
  end

  test "sender does not send event to subscribers if waiting one or more nodes", %{
    some_event: event,
    subscriber1: subscriber
  } do
    {:ok, sender} = Sender.start_link(nil)
    {:ok, root_node} = Node.start_link()
    {:ok, leaf_node} = Node.start_link()
    Sender.wait_node(sender, root_node)
    Sender.put_event(sender, event)

    Sender.put_subscribers_and_following_nodes(sender, root_node, [subscriber], [leaf_node])
    refute_receive {:trace, ^subscriber, :receive, ^event}
    Sender.put_subscribers_and_following_nodes(sender, leaf_node, [], [])
    assert_receive {:trace, ^subscriber, :receive, ^event}
  end

  test "sender exits", %{some_event: event} do
    {:ok, sender} = Sender.start_link(nil)
    {:ok, node} = Node.start_link()
    Process.monitor(sender)
    Sender.wait_node(sender, node)
    Sender.put_event(sender, event)

    refute_receive {:DOWN, _, _, _, _}
    Sender.put_subscribers_and_following_nodes(sender, node, [], [])
    assert_receive {:DOWN, _, _, _, _}
  end
end
