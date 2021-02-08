defmodule Cizen.Dispatcher.SenderTest do
  use ExUnit.Case

  alias Cizen.Dispatcher.{Node, Sender}

  defmodule(TestEvent, do: defstruct([]))

  setup do
    pid = self()
    event = %TestEvent{}

    subscriber1 =
      spawn(fn ->
        receive do
          ^event -> :ok
        end

        send(pid, :received_subscriber1)
      end)

    subscriber2 =
      spawn(fn ->
        receive do
          ^event -> :ok
        end

        send(pid, :received_subscriber2)
      end)

    {:ok, node} = Node.start_link()
    Node.put(node, true, subscriber1)
    Node.put(node, true, subscriber2)

    %{some_event: event, node: node, subscriber1: subscriber1, subscriber2: subscriber2}
  end

  test "sender sends event to subscribers", %{
    node: node,
    some_event: event
  } do
    {:ok, sender} = Sender.start_link(name: :a, root_node: node, next_sender: self())

    Sender.push(sender, event)
    Sender.allow_to_send(sender)

    assert_receive :received_subscriber1
    assert_receive :received_subscriber2
  end

  test "sender does not send event to subscribers if not allowed to send", %{
    node: node,
    some_event: event
  } do
    {:ok, sender} = Sender.start_link(name: :a, root_node: node, next_sender: self())

    Sender.push(sender, event)

    refute_receive :received_subscriber1
    Sender.allow_to_send(sender)
    assert_receive :received_subscriber1
  end

  test "sender sends an event to subscribers if allowed to send on startup", %{
    node: node,
    some_event: event
  } do
    {:ok, sender} =
      Sender.start_link(allowed_to_send?: true, name: :a, root_node: node, next_sender: self())

    Sender.push(sender, event)

    assert_receive :received_subscriber1
  end

  test "allow the next node to send an event after sent an event", %{some_event: event} do
    node = spawn_link(fn -> loop() end)
    {:ok, next} = Sender.start_link(name: :next, root_node: node, next_sender: self())
    next |> :erlang.trace(true, [:receive])
    {:ok, sender} = Sender.start_link(name: :a, root_node: node, next_sender: :next)
    Sender.push(sender, event)

    refute_receive {:trace, ^next, :receive, {:"$gen_cast", :allow_to_send}}
    Sender.allow_to_send(sender)
    assert_receive {:trace, ^next, :receive, {:"$gen_cast", :allow_to_send}}
  end

  defp loop do
    receive do
      _ -> loop()
    end
  end
end
