defmodule Cizen.Dispatcher.Intake do
  @moduledoc """
  The round-robin scheduler module that push an event to senders.
  """
  alias Cizen.Dispatcher.{Node, Sender}

  defp sender_name(index, sender_count), do: :"#{Sender}_#{rem(index, sender_count)}"

  def start_link do
    sender_count = System.schedulers_online()
    counter = :atomics.new(1, [{:signed, false}])
    :persistent_term.put(__MODULE__, {sender_count, counter})

    children =
      0..(sender_count - 1)
      |> Enum.map(fn i ->
        sender = sender_name(i, sender_count)
        next_sender = sender_name(i + 1, sender_count)

        %{
          id: sender,
          start:
            {Sender, :start_link,
             [[allowed_to_send?: i == 0, root_node: Node, next_sender: next_sender, name: sender]]}
        }
      end)

    Supervisor.start_link(children, strategy: :one_for_all)
  end

  def push(event) do
    Cizen.Dispatcher.log(event, __ENV__)
    {sender_count, counter} = :persistent_term.get(__MODULE__)
    Cizen.Dispatcher.log(event, __ENV__)
    counter = :atomics.add_get(counter, 1, 1) - 1
    Cizen.Dispatcher.log(event, __ENV__)
    Sender.push(sender_name(counter, sender_count), event)
  end
end
