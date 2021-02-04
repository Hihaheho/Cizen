defmodule Cizen.Dispatcher.IntakeTest do
  use ExUnit.Case

  alias Cizen.Dispatcher.Intake
  alias Cizen.Event

  defmodule(TestEvent, do: defstruct([]))

  test "pushes an event to sender" do
    event = Event.new(nil, %TestEvent{})

    {sender_count, counter} = :persistent_term.get(Intake)
    index = :atomics.get(counter, 1)

    sender = GenServer.whereis(:"#{Cizen.Dispatcher.Sender}_#{rem(index, sender_count)}")

    :erlang.trace(sender, true, [:receive])

    refute_receive {:trace, ^sender, :receive, {:"$gen_cast", {:push, ^event}}}
    Intake.push(event)
    assert_receive {:trace, ^sender, :receive, {:"$gen_cast", {:push, ^event}}}
  end

  test "increments index" do
    event = Event.new(nil, %TestEvent{})

    {_, counter} = :persistent_term.get(Intake)
    previous_index = :atomics.get(counter, 1)
    Intake.push(event)
    index = :atomics.get(counter, 1)
    assert index == previous_index + 1
  end
end
