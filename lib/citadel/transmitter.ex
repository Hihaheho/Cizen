defmodule Cizen.Transmitter do
  @moduledoc """
  Transmitter creates a connection for messaging.
  """

  use GenServer

  alias Cizen.Connection
  alias Cizen.Dispatcher
  alias Cizen.Event
  alias Cizen.SagaID
  alias Cizen.SagaLauncher
  alias Cizen.SagaRegistry

  alias Cizen.ReceiveMessage
  alias Cizen.SendMessage

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_args) do
    Dispatcher.listen_event_type(SendMessage)
    Dispatcher.listen_event_type(ReceiveMessage)
    {:ok, :ok}
  end

  @impl true
  def handle_info(%Event{body: %SendMessage{} = body}, state) do
    if body.channels == [] do
      Dispatcher.dispatch(
        Event.new(%ReceiveMessage{
          message: body.message
        })
      )
    else
      Dispatcher.dispatch(
        Event.new(%SagaLauncher.LaunchSaga{
          id: SagaID.new(),
          saga: %Connection{
            message: body.message,
            channels: body.channels
          }
        })
      )
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(%Event{body: %ReceiveMessage{message: message}} = event, state) do
    case SagaRegistry.resolve_id(message.destination_saga_id) do
      {:ok, pid} ->
        send(pid, event)

      _ ->
        :ok
    end

    {:noreply, state}
  end
end
