# Effect

An effect is a struct which abstracts a collection of interactions with sagas.

## Use Effect

You can use effects in a [Automaton](/automaton.html) or a handle block.
You can create a handle block like this:

    use Effectful # to use handle/1

    handle fn ->
      perform some_effect
    end

## Pre-defined Effects

Cizen has several pre-defined effects.
For convenience, you can alias all of them by;

    use Cizen.Effects # aliases all effects.

or only specified effects:

    use Cizen.Effects, only: [Subscribe, Receive, Dispatch]

### Effects for Event

- `Cizen.Effects.Subscribe` subscribes events by the given filter.
- `Cizen.Effects.Receive` receives an event which fulfills the given filter.
- `Cizen.Effects.Dispatch` dispatches an event with the given body.

### Effects for Saga

- `Cizen.Effects.Start` starts a saga by the given saga struct.
- `Cizen.Effects.End` ends a saga by its saga ID.
- `Cizen.Effects.Fork` forks a saga.
- `Cizen.Effects.Monitor` starts monitoring a saga.

### Effects Combinators

- `Cizen.Effects.All` performs all given effects.
- `Cizen.Effects.Chain` chains the given effects and performs them sequentially.
- `Cizen.Effects.Map` maps the result of the given effect.
- `Cizen.Effects.Race` starts a race between the given effects.

## Custom Effects

See `Cizen.Effect`.
