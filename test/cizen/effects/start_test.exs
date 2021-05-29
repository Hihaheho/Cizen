defmodule Cizen.Effects.StartTest do
  use Cizen.SagaCase
  alias Cizen.TestSaga

  alias Cizen.Dispatcher
  alias Cizen.Effects.Start
  alias Cizen.Pattern
  alias Cizen.Saga

  require Pattern

  defmodule(TestEvent, do: defstruct([:value]))

  describe "Start" do
    test "starts a saga" do
      pid = self()

      id =
        assert_handle(fn ->
          perform(%Start{
            saga: %TestSaga{
              on_start: fn _ -> send(pid, {:saga_id, Saga.self()}) end
            }
          })
        end)

      assert_receive {:saga_id, ^id}
    end

    defmodule DelayedSaga do
      use Saga

      defstruct []

      @impl true
      def on_start(_) do
        id = Saga.self()

        spawn_link(fn ->
          Process.send_after(self(), :ok, 200)

          receive do
            :ok -> Dispatcher.dispatch(%Saga.Started{saga_id: id})
          end
        end)

        {Saga.lazy_init(), :ok}
      end

      @impl true
      def handle_event(_, state), do: state
    end

    test "waits a Started event" do
      Dispatcher.listen(Pattern.new(fn %Saga.Started{} -> true end))

      id =
        assert_handle(fn ->
          perform(%Start{
            saga: %DelayedSaga{}
          })
        end)

      assert_receive %Saga.Started{saga_id: ^id}, 30
    end
  end
end
