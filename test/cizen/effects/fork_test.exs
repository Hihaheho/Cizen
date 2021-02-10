defmodule Cizen.Effects.ForkTest do
  use Cizen.SagaCase
  alias Cizen.TestSaga

  alias Cizen.Dispatcher
  alias Cizen.Effects.Fork
  alias Cizen.Filter
  alias Cizen.Saga

  defmodule(TestEvent, do: defstruct([]))

  defmodule TestAutomaton do
    alias Cizen.Automaton
    use Automaton
    defstruct [:pid]

    use Cizen.Effects

    @impl true
    def spawn(%__MODULE__{pid: pid}) do
      perform(%Subscribe{
        event_filter: Filter.new(fn %TestEvent{} -> true end)
      })

      forked =
        perform(%Fork{
          saga: %TestSaga{}
        })

      send(pid, forked)

      :next
    end

    @impl true
    def yield(:next) do
      perform %Receive{}
      Automaton.finish()
    end
  end

  test "forked saga finishes after forker saga finishes" do
    pid = self()

    assert_handle(fn ->
      perform(%Start{saga: %TestAutomaton{pid: pid}})
    end)

    forked =
      receive do
        forked -> forked
      end

    Dispatcher.listen_event_type(Saga.Finished)

    Dispatcher.dispatch(%TestEvent{})

    assert_receive %Saga.Finished{saga_id: ^forked}
  end
end
