# Event

Events are values (commonly struct or map) we listen and dispatch.

## Listen Events

    Cizen.Dispatcher.listen(
      Pattern.new(%PushMessage{})
    )

See `Cizen.Pattern` for details.

## Dispatch by Dispatcher

    Cizen.Dispatcher.dispatch(
      %PushMessage{to: "user A"}
    )

## Dispatch by Dispatch Effect

    use Cizen.Effectful
    use Cizen.Effects

    handle fn ->
      dispatched_event = perform %Dispatch{
        body: %PushMessage{to: "user A"}
      }
    end