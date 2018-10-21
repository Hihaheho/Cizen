defmodule Cizen.EventFilter do
  @moduledoc """
  Filter events.
  """

  alias Cizen.Event
  alias Cizen.EventBodyFilterSet
  alias Cizen.EventType
  alias Cizen.SagaID

  @type t :: %__MODULE__{
          event_type: EventType.t() | nil,
          source_saga_id: SagaID.t() | nil,
          source_saga_module: module | nil,
          event_body_filter_set: EventBodyFilterSet.t() | nil
        }

  defstruct [
    :event_type,
    :source_saga_id,
    :source_saga_module,
    :event_body_filter_set
  ]

  @doc """
  Test event by the given filter.
  """
  @spec test(__MODULE__.t(), Event.t()) :: boolean
  def test(event_filter, event) do
    test_source_saga_id(event_filter, event) and test_source_saga_module(event_filter, event) and
      test_event_type(event_filter, event) and test_event_body_filter_set(event_filter, event)
  end

  defp test_source_saga_id(event_filter, event) do
    if is_nil(event_filter.source_saga_id) do
      true
    else
      event_filter.source_saga_id == event.source_saga_id
    end
  end

  defp test_source_saga_module(event_filter, event) do
    if is_nil(event_filter.source_saga_module) do
      true
    else
      event_filter.source_saga_module == event.source_saga_module
    end
  end

  defp test_event_type(event_filter, event) do
    if is_nil(event_filter.event_type) do
      true
    else
      event_filter.event_type == Event.type(event)
    end
  end

  defp test_event_body_filter_set(event_filter, event) do
    if is_nil(event_filter.event_body_filter_set) do
      true
    else
      EventBodyFilterSet.test(event_filter.event_body_filter_set, event.body)
    end
  end

  @doc """
  Returns new event filter.

  The following keys are used to create an event filter, and all of them are optional:
    * `:event_type` - an event type.
    * `:source_saga_id` - a saga ID.
    * `:source_saga_module` - a module.
    * `:event_body_filters` - a list of event body filters.
  """
  defmacro new(params \\ []) do
    {event_type, params} = Keyword.pop(params, :event_type)
    {source_saga_id, params} = Keyword.pop(params, :source_saga_id)
    {source_saga_module, params} = Keyword.pop(params, :source_saga_module)
    {event_body_filters, params} = Keyword.pop(params, :event_body_filters, [])

    unless params == [] do
      raise ArgumentError, "invalid keys: #{inspect(params)}"
    end

    expanded = Macro.expand(event_type, __CALLER__)

    if not is_nil(event_type) and is_atom(expanded) do
      case Code.ensure_compiled(expanded) do
        {:error, _} ->
          raise ArgumentError, "invalid keys: #{inspect(params)}"

        _ ->
          :ok
      end
    end

    quote bind_quoted: [
            event_type: event_type,
            source_saga_id: source_saga_id,
            source_saga_module: source_saga_module,
            event_body_filters: event_body_filters
          ] do
      %Cizen.EventFilter{
        event_type: event_type,
        source_saga_id: source_saga_id,
        source_saga_module: source_saga_module,
        event_body_filter_set: EventBodyFilterSet.new(event_body_filters)
      }
    end
  end
end