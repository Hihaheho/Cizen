# Getting Started

Cizen is a library to build applications with automata and events.

For our getting started tutorial, we are going to create an automaton works like a stack.
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

      use Cizen.Request
      defresponse Item, :pop_event_id do
        defstruct [:item, :pop_event_id]
      end
    end

`Push` is an event to push an item to a stack,
and `Pop` is an event to pop an item from a stack.
To receive the popped item for a `Pop` event,
we made `Pop` requestive and define `Pop.Item`,
which is an event to return the popped item.

## Define an Automaton

Next, we define an automaton which handles the `Push` and `Pop`.

    defmodule Stack do
      use Cizen.Automaton
      defstruct [:stack]

      use Cizen.Effects # to use All, Subscribe, Receive, and Dispatch
      alias Cizen.Filter

      @impl true
      def spawn(id, %__MODULE__{stack: stack}) do
        perform id, %All{effects: [
          %Subscribe{event_filter: Filter.new(
            fn %Push{} -> true end
          )},
          %Subscribe{event_filter: Filter.new(
            fn %Pop{} -> true end
          )}
        ]}

        stack # next state
      end

      @impl true
      def yield(id, stack) do
        event = perform id, %Receive{}

        case event do
          %Push{item: item} ->
            [item | stack] # next state

          %Pop{} ->
            [item | tail] = stack

            perform id, %Dispatch{
              body: %Pop.Item{item: item, pop_event_id: event.id}
            }

            tail # next state
        end
      end
    end

There are two callbacks `spawn/2` and `yield/2`,
and they'll called with the following lifecycle:

1. First, `c:Cizen.Automaton.spawn/2` is called with a struct on start.
2. Then, `c:Cizen.Automaton.yield/2` is repeatedly called with a state.

> The first argument of the two callbacks is a saga ID, and we'll use it [later](#multiple-stacks) in this guide.

`Cizen.Automaton.perform/2` performs the given effect synchronously and returns the result of the effect.

> See [Effect](effect.html) for details.

The following code in `spawn/2` subscribes two event types `Push` and `Pop`:

    perform id, %All{effects: [
      %Subscribe{event_filter: Filter.new(
        fn %Push{} -> true end
      )},
      %Subscribe{event_filter: Filter.new(
        fn %Pop{} -> true end
      )}
    ]}

Based on the subscriptions, events are stored in a event queue, which all automata have,
and `Receive` effect dequeues the first event from the queue.

> `%Receive{}` is the same as `%Receive{event_filter: Filter.new(fn _ -> true end)}`,
> and `Filter.new(fn _ -> true end)` returns an filter that matches with all events.
> Actually, `Receive` effect dequeues the first event **which matches with the given filter** from the queue.

In the following code in `yield/2`, we assign `event.id` to `:pop_event_id`
to link the `Pop.Item` event with the received `Pop` event:

    perform id, %Dispatch{
      body: %Pop.Item{item: item, pop_event_id: event.id}
    }

## Interact with Automata

Now, we can interact with the automaton and events like this:

    defmodule Main do
      def main do
        use Cizen.Effectful
        use Cizen.Effects

        handle fn id ->
          # start stack
          perform id, %Start{
            saga: %Stack{stack: [:a]}
          }

          item_event = perform id, %Request{
            body: %Pop{}
          }
          %Pop.Item{item: item} = item_event
          IO.puts(item) # => a

          perform id, %Dispatch{
            body: %Push{item: :b}
          }

          perform id, %Dispatch{
            body: %Push{item: :c}
          }

          item_event = perform id, %Request{
            body: %Pop{}
          }
          %Pop.Item{item: item} = item_event
          IO.puts(item) # => c

          item_event = perform id, %Request{
            body: %Pop{}
          }
          %Pop.Item{item: item} = item_event
          IO.puts(item) # => b
        end
      end
    end

Normally, `Cizen.Automaton.perform/2` only works in automaton callbacks,
so we use `Cizen.Effectful.handle/1` to interact with the automaton from outside of the automata world.

## Multiple Stacks

Our code works well only with just one stack.
It's broken if we have multiple stacks because all stacks receive `Push` or `Pop` event when we dispatch.
To avoid it, let's introduce event body filters.

First, add `:stack_id` and definitions of event body filters in the events:

    defmodule Push do
      defstruct [:stack_id, :item]
    end

    defmodule Pop do
      defstruct [:stack_id]

      use Cizen.Request
      defresponse Item, :pop_event_id do
        defstruct [:item, :pop_event_id]
      end
    end

Next, use the filters on subscribe in `Stack.spawn/2`:

    def spawn(id, %__MODULE__{stack: stack}) do
      perform id, %All{effects: [
        %Subscribe{event_filter: Filter.new(
          fn %Push{stack_id: stack_id} ->
            stack_id == id
          end
        )},
        %Subscribe{event_filter: Filter.new(
          fn %Pop{stack_id: stack_id} ->
            stack_id == id
          end
        )},
      ]}

      stack # next state
    end

Finally, we can handle multiple stacks like this:

    defmodule Main do
      def main do
        use Cizen.Effectful
        use Cizen.Effects

        handle fn id ->
          # start stack A
          stack_a = perform id, %Start{saga: %Stack{stack: []}}

          # start stack B
          stack_b = perform id, %Start{saga: %Stack{stack: []}}

          # push to the stack A
          perform id, %Dispatch{
            body: %Push{stack_id: stack_a, item: :a}
          }

          # push to the stack B
          perform id, %Dispatch{
            body: %Push{stack_id: stack_b, item: :b}
          }

          # push to the stack B
          perform id, %Dispatch{
            body: %Push{stack_id: stack_b, item: :c}
          }

          # pop from the stack A
          item_event = perform id, %Request{
            body: %Pop{stack_id: stack_a}
          }
          %Pop.Item{item: item} = item_event
          IO.puts(item) # => a

          # pop from the stack B
          item_event = perform id, %Request{
            body: %Pop{stack_id: stack_b}
          }
          %Pop.Item{item: item} = item_event
          IO.puts(item) # => c

          # pop from the stack B
          item_event = perform id, %Request{
            body: %Pop{stack_id: stack_b}
          }
          %Pop.Item{item: item} = item_event
          IO.puts(item) # => b
        end
      end
    end
