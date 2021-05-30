defmodule Cizen.Dispatcher do
  @moduledoc """
  The dispatcher.
  """

  alias Cizen.Dispatcher.{Intake, Node}
  alias Cizen.Event
  alias Cizen.Pattern
  alias Cizen.Saga

  require Pattern

  @doc false
  def start_link do
    Node.initialize()
    :ets.new(__MODULE__, [:set, :public, :named_table, {:write_concurrency, true}])
    Intake.start_link()
  end

  @doc """
  Dispatch the event.
  """
  @spec dispatch(Event.t()) :: :ok
  def dispatch(event) do
    Intake.push(event)
  end

  @doc """
  Listen all events.
  """
  @spec listen_all :: :ok
  def listen_all do
    listen(Pattern.new(_))
  end

  @doc """
  Listen the specific event type.
  """
  @spec listen_event_type(module) :: :ok
  def listen_event_type(event_type) do
    listen(Pattern.new(fn %{} = event -> event.__struct__ == event_type end))
  end

  @doc """
  Listen events with the given event filter.
  """
  def listen(pattern) do
    listen_with_pid(self(), pattern.code)
  end

  @doc """
  Listen events with the given event filter for the given saga ID.
  """
  def listen(subscriber, pattern) do
    case Saga.get_pid(subscriber) do
      {:ok, pid} ->
        listen_with_pid(pid, pattern.code)

      _ ->
        :ok
    end
  end

  defp listen_with_pid(pid, code) do
    Node.put(code, pid)
  end
end
