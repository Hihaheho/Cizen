defmodule Cizen.CrashLogger do
  @moduledoc """
  A logger to log Saga.Crashed events.
  """

  use Cizen.Automaton

  defstruct []

  alias Cizen.Effects.{Receive, Subscribe}
  alias Cizen.Filter
  alias Cizen.Saga

  require Logger

  def spawn(%__MODULE__{}) do
    perform(%Subscribe{
      event_filter: Filter.new(fn %Saga.Crashed{} -> true end)
    })

    :loop
  end

  def yield(:loop) do
    crashed_event = perform %Receive{}

    %Saga.Crashed{
      saga_id: saga_id,
      saga: saga,
      reason: reason,
      stacktrace: stacktrace
    } = crashed_event

    message = """
    saga #{saga_id} is crashed
    #{inspect(saga)}
    """

    Logger.error(message <> Exception.format(:error, reason, stacktrace))

    :loop
  end
end
