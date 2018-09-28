defmodule Citadel.EventFilterSubscription do
  @moduledoc """
  A struct to represent event subscription.
  """

  alias Citadel.Event
  alias Citadel.EventFilter
  alias Citadel.SagaID

  @type t :: %__MODULE__{
          subscriber_saga_id: SagaID.t(),
          subscriber_saga_module: module | nil,
          event_filter: EventFilter.t()
        }

  @enforce_keys [:subscriber_saga_id, :event_filter]
  defstruct [
    :subscriber_saga_id,
    :subscriber_saga_module,
    :event_filter
  ]

  @spec match?(__MODULE__.t(), Event.t()) :: boolean
  def match?(subscription, event) do
    EventFilter.test(subscription.event_filter, event)
  end
end