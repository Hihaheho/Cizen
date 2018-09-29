defmodule Citadel.EventFilterDispatcher.EventPusher do
  @moduledoc """
  Push event to subscribers
  """

  use GenServer

  alias Citadel.Dispatcher
  alias Citadel.Event
  alias Citadel.EventFilterDispatcher.PushEvent
  alias Citadel.SagaRegistry

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_args) do
    Dispatcher.listen_event_type(PushEvent)
    {:ok, :ok}
  end

  @impl true
  def handle_info(%Event{body: %PushEvent{}} = event, state) do
    subscriber_saga_id = hd(event.body.subscriptions).subscriber_saga_id

    case SagaRegistry.resolve_id(subscriber_saga_id) do
      {:ok, pid} -> send(pid, event)
      _ -> :ok
    end

    {:noreply, state}
  end
end