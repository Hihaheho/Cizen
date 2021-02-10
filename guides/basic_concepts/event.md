# Event

## Event Struct

A struct of `Cizen.Event` has the following four fields:

- `:id` an unique ID for the event.
- `:body` a struct.
- `:source_saga_id` a saga ID of the source of the event.
- `:source_saga` a saga struct the source of the event.

## Creating a Event

Any struct can be an event:

    event = %PushMessage{to: "user A"}

## Dispatching Event

### With Dispatcher

    Cizen.Dispatcher.dispatch(
      %PushMessage{to: "user A"}
    )

### With Dispatch Effect

    use Cizen.Effectful
    use Cizen.Effects

    handle fn ->
      dispatched_event = perform %Dispatch{
        body: %PushMessage{to: "user A"}
      }
    end