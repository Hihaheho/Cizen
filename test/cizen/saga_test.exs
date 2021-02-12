defmodule Cizen.SagaTest do
  use Cizen.SagaCase
  doctest Cizen.Saga

  alias Cizen.TestHelper
  alias Cizen.TestSaga

  import Cizen.TestHelper,
    only: [
      launch_test_saga: 0,
      launch_test_saga: 1,
      assert_condition: 2
    ]

  alias Cizen.Dispatcher
  alias Cizen.Saga
  alias Cizen.SagaID

  defmodule(TestEvent, do: defstruct([:value]))

  describe "Saga" do
    test "dispatches Launched event on launch" do
      Dispatcher.listen_event_type(Saga.Started)
      id = launch_test_saga()
      assert_receive %Saga.Started{saga_id: ^id}
    end

    test "finishes on Finish event" do
      Dispatcher.listen_event_type(Saga.Started)
      id = launch_test_saga()
      Dispatcher.dispatch(%Saga.Finish{saga_id: id})
      assert_condition(100, :error == Saga.get_pid(id))
    end

    test "does not finish on Finish event for other saga" do
      pid = self()
      Dispatcher.listen_event_type(Saga.Started)

      id =
        launch_test_saga(
          handle_event: fn event, state ->
            send(pid, event)
            state
          end
        )

      finish = %Saga.Finish{saga_id: SagaID.new()}
      Saga.send_to(id, finish)
      assert_receive ^finish
      assert {:ok, _} = Saga.get_pid(id)
    end

    test "dispatches Finished event on finish" do
      Dispatcher.listen_event_type(Saga.Finished)
      id = launch_test_saga()
      Dispatcher.dispatch(%Saga.Finish{saga_id: id})
      assert_receive %Saga.Finished{saga_id: ^id}
    end

    defmodule(CrashTestEvent1, do: defstruct([]))

    test "terminated on crash" do
      TestHelper.surpress_crash_log()

      id =
        launch_test_saga(
          on_start: fn _state ->
            Dispatcher.listen_event_type(CrashTestEvent1)
          end,
          handle_event: fn body, state ->
            case body do
              %CrashTestEvent1{} ->
                raise "Crash!!!"

              _ ->
                state
            end
          end
        )

      Dispatcher.dispatch(%CrashTestEvent1{})
      assert_condition(100, :error == Saga.get_pid(id))
    end

    defmodule(CrashTestEvent2, do: defstruct([]))

    test "dispatches Crashed event on crash" do
      TestHelper.surpress_crash_log()

      Dispatcher.listen_event_type(Saga.Crashed)

      id =
        launch_test_saga(
          on_start: fn _state ->
            Dispatcher.listen_event_type(CrashTestEvent2)
          end,
          handle_event: fn body, state ->
            case body do
              %CrashTestEvent2{} ->
                raise "Crash!!!"

              _ ->
                state
            end
          end
        )

      Dispatcher.dispatch(%CrashTestEvent2{})

      assert_receive %Saga.Crashed{
        saga_id: ^id,
        reason: %RuntimeError{},
        stacktrace: [{__MODULE__, _, _, _} | _]
      }
    end

    defmodule(TestEventReply, do: defstruct([:value]))

    test "handles events" do
      Dispatcher.listen_event_type(TestEventReply)

      id =
        launch_test_saga(
          on_start: fn _state ->
            Dispatcher.listen_event_type(TestEvent)
          end,
          handle_event: fn body, state ->
            case body do
              %TestEvent{value: value} ->
                Dispatcher.dispatch(%TestEventReply{value: value})
                state

              _ ->
                state
            end
          end
        )

      Dispatcher.dispatch(%TestEvent{value: id})
      assert_receive %TestEventReply{value: ^id}
    end

    test "finishes immediately" do
      Dispatcher.listen_event_type(Saga.Finished)

      id =
        launch_test_saga(
          on_start: fn state ->
            id = Saga.self()
            Dispatcher.dispatch(%Saga.Finish{saga_id: id})
            state
          end
        )

      assert_receive %Saga.Finished{saga_id: ^id}
      assert_condition(100, :error == Saga.get_pid(id))
    end

    defmodule LazyLaunchSaga do
      use Cizen.Saga

      defstruct []

      @impl true
      def on_start(_) do
        Dispatcher.listen_event_type(TestEvent)
        {Saga.lazy_init(), :ok}
      end

      @impl true
      def handle_event(%TestEvent{}, :ok) do
        id = Saga.self()
        Dispatcher.dispatch(%Saga.Started{saga_id: id})
        :ok
      end
    end

    test "does not dispatch Launched event on lazy launch" do
      Dispatcher.listen_event_type(Saga.Started)
      {:ok, id} = Saga.start(%LazyLaunchSaga{}, return: :saga_id)
      refute_receive %Saga.Started{saga_id: ^id}
      Dispatcher.dispatch(%TestEvent{})
      assert_receive %Saga.Started{saga_id: ^id}
    end
  end

  describe "Saga.module/1" do
    test "returns the saga module" do
      assert Saga.module(%TestSaga{}) == TestSaga
    end
  end

  describe "Saga.start/2" do
    test "starts a saga" do
      Dispatcher.listen_event_type(Saga.Started)
      {:ok, pid} = Saga.start(%TestSaga{extra: :some_value})

      assert_receive %Saga.Started{saga_id: id}

      assert {:ok, ^pid} = Saga.get_pid(id)
    end

    test "raises an error when called with unknown option" do
      assert_raise ArgumentError, "invalid argument(s): [:unknown_key]", fn ->
        Saga.start(%TestSaga{extra: :some_value}, unknown_key: :exists)
      end
    end

    test "resumes a saga" do
      Dispatcher.listen_event_type(Saga.Resumed)
      {:ok, pid} = Saga.start(%TestSaga{extra: :some_value}, resume: :resumed_state)

      assert_receive %Saga.Resumed{saga_id: id}

      assert {:ok, ^pid} = Saga.get_pid(id)
      assert :resumed_state == :sys.get_state(pid).state
    end

    test "starts a saga with a specific saga ID" do
      Dispatcher.listen_event_type(Saga.Started)
      saga_id = SagaID.new()
      {:ok, pid} = Saga.start(%TestSaga{extra: :some_value}, saga_id: saga_id)

      assert_receive %Saga.Started{saga_id: ^saga_id}

      assert {:ok, ^pid} = Saga.get_pid(saga_id)
    end

    test "returns a saga ID" do
      Dispatcher.listen_event_type(Saga.Started)
      {:ok, saga_id} = Saga.start(%TestSaga{extra: :some_value}, return: :saga_id)

      assert_receive %Saga.Started{saga_id: ^saga_id}
    end

    test "finishes when the given lifetime process exits" do
      lifetime =
        spawn(fn ->
          receive do
            :finish -> :ok
          end
        end)

      {:ok, saga_id} =
        Saga.start(%TestSaga{extra: :some_value}, lifetime: lifetime, return: :saga_id)

      assert {:ok, _} = Saga.get_pid(saga_id)

      send(lifetime, :finish)

      assert_condition(100, :error == Saga.get_pid(saga_id))
    end

    test "finishes when the given lifetime saga exits" do
      lifetime = TestHelper.launch_test_saga()

      {:ok, saga_id} =
        Saga.start(%TestSaga{extra: :some_value}, lifetime: lifetime, return: :saga_id)

      assert {:ok, _} = Saga.get_pid(saga_id)

      Saga.stop(lifetime)

      assert_condition(100, :error == Saga.get_pid(saga_id))
    end

    test "finishes immediately when the given lifetime saga already ended" do
      # No pid
      lifetime = SagaID.new()

      {:ok, saga_id} =
        Saga.start(%TestSaga{extra: :some_value}, lifetime: lifetime, return: :saga_id)

      assert_condition(10, :error == Saga.get_pid(saga_id))
    end
  end

  describe "Saga.start_link/2" do
    test "starts a saga linked to the current process" do
      {:ok, pid} = Saga.start_link(%TestSaga{extra: :some_value})

      links = self() |> Process.info() |> Keyword.fetch!(:links)
      assert pid in links
      Process.unlink(pid)
    end
  end

  describe "Saga.get_pid/1" do
    test "launched saga is registered" do
      id = launch_test_saga()
      assert {:ok, _pid} = Saga.get_pid(id)
    end

    test "killed saga is unregistered" do
      id = launch_test_saga()
      assert {:ok, pid} = Saga.get_pid(id)
      true = Process.exit(pid, :kill)
      assert_condition(100, :error == Saga.get_pid(id))
    end
  end

  defmodule TestSagaState do
    use Cizen.Saga
    defstruct [:value]
    @impl true
    def on_start(%__MODULE__{}) do
      :ok
    end

    @impl true
    def handle_event(_event, :ok) do
      :ok
    end
  end

  describe "Saga.get_saga/1" do
    test "returns a saga struct" do
      {:ok, id} = Saga.start(%TestSagaState{value: :some_value}, return: :saga_id)

      assert {:ok, %TestSagaState{value: :some_value}} = Saga.get_saga(id)
    end

    test "returns error for unregistered saga" do
      assert :error == Saga.get_saga(SagaID.new())
    end
  end

  describe "Saga.send_to/2" do
    test "sends an event to a saga" do
      pid = self()

      id =
        launch_test_saga(
          handle_event: fn event, _state ->
            id = Saga.self()
            send(pid, {id, event})
          end
        )

      Saga.send_to(id, %TestEvent{value: 10})
      assert_receive {^id, %TestEvent{value: 10}}
    end
  end

  describe "Saga.resume/3" do
    test "starts a saga" do
      saga_id = SagaID.new()
      {:ok, pid} = Saga.resume(saga_id, %TestSaga{}, nil)

      assert {:ok, ^pid} = Saga.get_pid(saga_id)
    end

    test "does not invoke init callback" do
      pid = self()
      saga_id = SagaID.new()

      {:ok, _pid} =
        Saga.resume(
          saga_id,
          %TestSaga{
            on_start: fn _saga ->
              send(pid, :called_init)
            end
          },
          nil
        )

      refute_receive :called_init
    end

    test "invokes resume callback with arguments" do
      pid = self()
      saga_id = SagaID.new()

      {:ok, _pid} =
        Saga.resume(
          saga_id,
          %TestSaga{
            on_resume: fn saga, state ->
              send(pid, {Saga.self(), saga, state})
            end,
            extra: 42
          },
          :state
        )

      assert_receive {^saga_id, %TestSaga{extra: 42}, :state}
    end

    test "uses a resume callback's result as the next state" do
      pid = self()
      saga_id = SagaID.new()

      {:ok, _pid} =
        Saga.resume(
          saga_id,
          %TestSaga{
            on_resume: fn _saga, _state ->
              :next_state
            end,
            handle_event: fn _event, state ->
              send(pid, state)
            end
          },
          nil
        )

      Saga.send_to(saga_id, %TestEvent{})

      assert_receive :next_state
    end

    test "dispatches Resumed event" do
      Dispatcher.listen_event_type(Saga.Resumed)
      saga_id = SagaID.new()

      {:ok, _pid} =
        Saga.resume(
          saga_id,
          %TestSaga{},
          nil
        )

      assert_receive %Saga.Resumed{saga_id: ^saga_id}
    end

    defmodule TestSagaNoResume do
      use Saga
      defstruct [:value]

      @impl true
      def on_start(saga) do
        Dispatcher.dispatch(%TestEvent{value: {:called_init, saga}})
        :state
      end

      @impl true
      def handle_event(event, state) do
        Dispatcher.dispatch(%TestEvent{value: {:called_handle_event, event, state}})

        :next_state
      end
    end

    test "invokes init instead of resume when resume is not defined" do
      saga_id = SagaID.new()
      saga = %TestSagaNoResume{value: :some_value}
      Dispatcher.listen_event_type(TestEvent)

      {:ok, _pid} =
        Saga.resume(
          saga_id,
          saga,
          nil
        )

      assert_receive %TestEvent{value: {:called_init, ^saga}}
    end

    test "use the given state as next state" do
      saga_id = SagaID.new()
      Dispatcher.listen_event_type(TestEvent)

      {:ok, _pid} =
        Saga.resume(
          saga_id,
          %TestSagaNoResume{},
          :resumed_state
        )

      receive do
        %TestEvent{value: {:called_init, _}} -> :ok
      end

      event = %TestEvent{value: :some_value}
      Saga.send_to(saga_id, event)

      assert_receive %TestEvent{value: {:called_handle_event, ^event, :resumed_state}}
    end
  end

  describe "Saga.self/0" do
    defmodule TestSagaSelf do
      use Saga
      defstruct [:pid]

      @impl true
      def on_start(saga) do
        send(saga.pid, Saga.self())
        saga
      end

      @impl true
      def handle_event(_event, saga) do
        saga
      end
    end

    test "invokes init instead of resume when resume is not defined" do
      {:ok, saga_id} = Saga.start(%TestSagaSelf{pid: self()}, return: :saga_id)

      assert_receive ^saga_id
    end
  end

  defmodule TestSagaGenServer do
    use Saga
    defstruct []

    @impl true
    def on_start(_saga) do
      []
    end

    @impl true
    def handle_event(_event, saga) do
      saga
    end

    @impl true
    def handle_call(:pop, from, [head | tail]) do
      Saga.reply(from, head)
      tail
    end

    @impl true
    def handle_cast({:push, item}, state) do
      [item | state]
    end
  end

  describe "handle_call/3 and handle_cast/3" do
    test "works with Saga.call/2 and Saga.cast/2" do
      saga_id = SagaID.new()
      {:ok, pid} = Saga.start(%TestSagaGenServer{}, saga_id: saga_id)

      Saga.cast(saga_id, {:push, :a})
      assert :sys.get_state(pid) == [:a]

      assert Saga.call(saga_id, :pop) == :a
      assert :sys.get_state(pid) == []
    end
  end
end
