# Getting Started

Cizen is a library to build applications with automata and events.

## Cizen Tutorial

See [Primality Testing in Elixir using Cizen](https://ryo33.medium.com/primality-testing-in-elixir-using-cizen-8e2f5a39e467)

## Automaton Tutorial

For our getting started, we are going to create an automaton works like a stack.
The automaton will work like the following implementation with `GenServer`:

    defmodule Stack do
      use GenServer

      @impl true
      def init(stack) do
        {:ok, stack}
      end

      @impl true
      def handle_call(:pop, _from, [item | tail]) do
        {:reply, item, tail}
      end

      @impl true
      def handle_cast({:push, item}, state) do
        {:noreply, [item | state]}
      end
    end

    GenServer.start_link(Stack, [:a], name: Stack)

    item = GenServer.call(Stack, :pop)
    IO.puts(item) # => :a

    GenServer.cast(Stack, {:push, :b})

    GenServer.cast(Stack, {:push, :c})

    item = GenServer.call(Stack, :pop)
    IO.puts(item) # => :c

    item = GenServer.call(Stack, :pop)
    IO.puts(item) # => :b

## Define Events

At first, define two events, `Push` and `Pop`:

    defmodule Push do
      defstruct [:item]
    end

    defmodule Pop do
      defstruct []
    end

`Push` is an event to push an item to a stack,
and `Pop` is an event to pop an item from a stack.
To receive the popped item for a `Pop` event, we define `Pop.Item`,
which is an event to return the popped item.

Notes: This example uses struct but you can also use just maps or values.

## Define an Automaton

Next, we define an automaton which handles the `Push` and `Pop`.

    defmodule Stack do
      use Cizen.Automaton
      defstruct [:stack]

      use Cizen.Effects # to use All, Subscribe, Receive, and Dispatch
      alias Cizen.Pattern
      require Pattern

      @impl true
      def spawn(%__MODULE__{stack: stack}) do
        perform %All{effects: [
          %Subscribe{pattern: Pattern.new(%Push{})},
          %Subscribe{pattern: Pattern.new(%Pop{})}
        ]}

        stack # next state
      end

      @impl true
      def yield(stack) do
        event = perform %Receive{}

        case event do
          %Push{item: item} ->
            [item | stack] # next state

          %Call{from: from, request: %Pop{}} ->
            [item | tail] = stack

            Saga.reply(item)

            tail # next state
        end
      end
    end

There are two callbacks `spawn/2` and `yield/2`,
and they'll called with the following lifecycle:

1. First, `c:Cizen.Automaton.spawn/2` is called with a struct on start.
2. Then, `c:Cizen.Automaton.yield/2` is repeatedly called with a state.

`Cizen.Automaton.perform/1` performs the given effect synchronously and returns the result of the effect.

> See [Effect](effect.html) for details.

The following code in `spawn/2` subscribes two event types `Push` and `Pop`:

    perform %All{effects: [
      %Subscribe{pattern: Pattern.new(%Push{})},
      %Subscribe{pattern: Pattern.new(%Pop{})}
    ]}

Based on the subscriptions, events are stored in a event queue, which all automata have,
and `Receive` effect dequeues the first event from the queue.

> `%Receive{}` is the same as `%Receive{pattern: Pattern.new(_)}`,
> and `Pattern.new(_)` returns an event pattern that matches to all events.
> Actually, `Receive` effect dequeues the first event **which matches with the given filter** from the queue.

## Interact with Automata

Now, we can interact with the automaton and events like this:

    defmodule Main do
      def main do
        use Cizen.Effectful
        use Cizen.Effects

        handle fn ->
          # start stack
          stack = perform %Start{
            saga: %Stack{stack: [:a]}
          }

          # TODO use Call effect (not implemented yet).
          item = Saga.call(stack, %Pop{})
          IO.puts(item) # => a

          perform %Dispatch{
            body: %Push{item: :b}
          }

          perform %Dispatch{
            body: %Push{item: :c}
          }

          item = Saga.call(stack, %Pop{})
          IO.puts(item) # => c

          item = Saga.call(stack, %Pop{})
          IO.puts(item) # => b
        end
      end
    end

Normally, `Cizen.Automaton.perform/2` only works in automaton callbacks,
so we use `Cizen.Effectful.handle/1` to interact with the automaton from outside of the automata world.

## Multiple Stacks

Our code works well only with just one stack.
It's broken if we have multiple stacks because all stacks receive `Push` or `Pop` event when we dispatch.
To avoid it, let's introduce more complex pattern.

First, add `:stack_id` and definitions of event body filters in the events:

    defmodule Push do
      defstruct [:stack_id, :item]
    end

    defmodule Pop do
      defstruct []
    end

Next, use the filters on subscribe in `Stack.spawn/2`:

    def spawn(%__MODULE__{stack: stack}) do
      perform %All{effects: [
        %Subscribe{pattern: Pattern.new(%Push{stack_id: ^id})},
        %Subscribe{pattern: Pattern.new(%Pop{})}
      ]}

      stack # next state
    end

Finally, we can handle multiple stacks like this:

    defmodule Main do
      def main do
        use Cizen.Effectful
        use Cizen.Effects

        handle fn ->
          # start stack A
          stack_a = perform %Start{saga: %Stack{stack: []}}

          # start stack B
          stack_b = perform %Start{saga: %Stack{stack: []}}

          # push to the stack A
          perform %Dispatch{
            body: %Push{stack_id: stack_a, item: :a}
          }

          # push to the stack B
          perform %Dispatch{
            body: %Push{stack_id: stack_b, item: :b}
          }

          # push to the stack B
          perform %Dispatch{
            body: %Push{stack_id: stack_b, item: :c}
          }

          # pop from the stack A
          item = Saga.call(stack_a, %Pop{})
          IO.puts(item) # => a

          # pop from the stack B
          item = Saga.call(stack_b, %Pop{})
          IO.puts(item) # => c

          # pop from the stack B
          item = Saga.call(stack_b, %Pop{})
          IO.puts(item) # => b
        end
      end
    end
