defmodule Cizen.Effects.ResumeTest do
  use Cizen.SagaCase

  alias Cizen.Dispatcher
  alias Cizen.Filter
  alias Cizen.Saga
  alias Cizen.SagaID
  alias Cizen.TestSaga

  alias Cizen.Effects.Resume

  require Filter

  describe "Resume" do
    test "resume a saga" do
      pid = self()
      saga_id = SagaID.new()
      state = :some_state

      assert ^saga_id =
               assert_handle(fn ->
                 perform(%Resume{
                   id: saga_id,
                   saga: %TestSaga{
                     on_resume: fn saga, state -> send(pid, {Saga.self(), saga, state}) end,
                     extra: 42
                   },
                   state: state
                 })
               end)

      assert_receive {^saga_id, %TestSaga{extra: 42}, ^state}
    end

    defmodule DelayedSaga do
      use Saga

      defstruct []

      @impl true
      def on_start(_) do
        spawn_link(fn ->
          Process.send_after(self(), :ok, 200)

          receive do
            :ok -> Dispatcher.dispatch(%Saga.Resumed{saga_id: Saga.self()})
          end
        end)

        {Saga.lazy_init(), :ok}
      end

      @impl true
      def handle_event(_, state), do: state
    end

    test "waits a Resumed event" do
      Dispatcher.listen(Filter.new(fn %Saga.Resumed{} -> true end))

      id =
        assert_handle(fn ->
          perform(%Resume{
            id: SagaID.new(),
            saga: %DelayedSaga{},
            state: :some_state
          })
        end)

      assert_receive %Saga.Resumed{saga_id: ^id}, 30
    end
  end
end
