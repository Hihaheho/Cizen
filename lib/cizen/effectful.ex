defmodule Cizen.Effectful do
  @moduledoc """
  Creates a block which can perform effects.

  ## Example
      use Cizen.Effectful

      handle(fn ->
        some_result = perform some_effect
        if some_result do
          perform other_effect
        end
      end)
  """

  alias Cizen.Saga
  alias Cizen.SagaID

  defmacro __using__(_opts) do
    quote do
      import Cizen.Effectful, only: [handle: 1]
      import Cizen.Automaton, only: [perform: 1]
      require Cizen.Filter
    end
  end

  defmodule InstantAutomaton do
    @moduledoc false
    alias Cizen.Automaton
    use Automaton

    defstruct [:block]

    @impl true
    def spawn(struct) do
      struct
    end

    @impl true
    def yield(%__MODULE__{block: block}) do
      block.()
      Automaton.finish()
    end
  end

  def handle(func) do
    task =
      Task.async(fn ->
        pid = self()

        Saga.start_saga(
          SagaID.new(),
          %InstantAutomaton{
            block: fn ->
              send(pid, func.())
            end
          },
          pid
        )

        receive do
          result -> result
        end
      end)

    Task.await(task, :infinity)
  end
end
