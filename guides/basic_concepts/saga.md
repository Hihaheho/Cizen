# Saga

A saga is a process which handles events.

## Saga Module and Saga Struct

A saga module is a module which implements `Cizen.Saga` behaviour and defines a struct.
We call the defined struct "saga struct" and use it for starting sagas.

### Example

    defmodule SomeSaga do
      use Cizen.Saga
      defstruct [:some_field]

      @impl true
      def on_start(%__MODULE__{some_field: value}) do
        # Initialize and returns a next state
      end

      @impl true
      def handle_event(event, state) do
        # Handle events and returns a next state
      end
    end

## Start a Saga

### Normal way

    Saga.start(%SomeSaga{some_field: :some_value})

### With an Effect

    use Cizen.Effectful
    use Cizen.Effects

    handle fn ->
      started_saga_id = perform %Start{saga: %SomeSaga{some_field: :some_value}}
    end

## As a Part of a Supervision Tree

    children = [
      %{
        id: :some_id,
        start: {Saga, :start_link, [%SomeSaga{some_field: :some_value}]}
      }
    ]
    Supervisor.start_link(children, strategy: :one_for_one)

## Automaton

`Cizen.Automaton` module is a saga framework that allows you to use effects in callbacks.
See [Define an Automaton](getting_started.html#define-an-automaton).
