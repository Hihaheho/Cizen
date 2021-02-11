defmodule Cizen.AutomatonTest do
  use Cizen.SagaCase
  alias Cizen.EffectHandlerTestHelper.{TestEffect, TestEvent}
  alias Cizen.TestHelper

  alias Cizen.Automaton
  alias Cizen.Dispatcher
  alias Cizen.Filter
  alias Cizen.Saga
  alias Cizen.SagaID

  require Filter

  defmodule(UnknownEvent, do: defstruct([]))

  describe "perform/1" do
    test "block until message is coming and returns the message" do
      import Automaton, only: [perform: 1]
      current = self()

      pid =
        spawn_link(fn ->
          assert :value == perform(%TestEffect{value: :a})
          send(current, :ok)
        end)

      refute_receive :ok
      send(pid, :value)
      assert_receive :ok
    end
  end

  describe "Automaton" do
    defmodule TestAutomatonNotFinish do
      use Automaton

      defstruct []

      @impl true
      def spawn(state) do
        state
      end

      @impl true
      def yield(state) do
        :timer.sleep(100)
        state
      end
    end

    test "does not finishes" do
      saga_id = SagaID.new()
      Dispatcher.listen(Filter.new(fn %Saga.Finish{saga_id: ^saga_id} -> true end))

      Saga.start_link(%TestAutomatonNotFinish{}, saga_id: saga_id)

      refute_receive %Saga.Finish{saga_id: ^saga_id}
    end

    defmodule TestAutomatonFinishOnSpawn do
      use Automaton

      defstruct []

      @impl true
      def spawn(%__MODULE__{}) do
        Automaton.finish()
      end

      @impl true
      def yield(_state), do: :ok
    end

    test "finishes when spawn/2 returns Automaton.finish()" do
      saga_id = SagaID.new()
      Dispatcher.listen(Filter.new(fn %Saga.Finish{saga_id: ^saga_id} -> true end))

      Saga.start(%TestAutomatonFinishOnSpawn{}, saga_id: saga_id)

      assert_receive %Saga.Finish{saga_id: ^saga_id}
    end

    defmodule TestAutomaton do
      use Automaton

      defstruct [:pid]

      @impl true
      def spawn(%__MODULE__{pid: pid}) do
        Dispatcher.listen(Saga.self(), Filter.new(fn %TestEvent{} -> true end))

        send(pid, :spawned)
        send(pid, perform(%TestEffect{value: :a}))
        {:b, pid}
      end

      @impl true
      def respawn(%__MODULE__{pid: pid}, _) do
        Dispatcher.listen(Saga.self(), Filter.new(fn %TestEvent{} -> true end))

        send(pid, :respawned)
        send(pid, perform(%TestEffect{value: :a}))
        {:b, pid}
      end

      @impl true
      def yield({:b, pid}) do
        send(pid, perform(%TestEffect{value: :b}))
        {:c, pid}
      end

      def yield({:c, pid}) do
        send(pid, perform(%TestEffect{value: :c}))
        Automaton.finish()
      end
    end

    test "works with perform" do
      saga_id = SagaID.new()
      Dispatcher.listen(Filter.new(fn %Saga.Finish{saga_id: ^saga_id} -> true end))

      Saga.start_link(%TestAutomaton{pid: self()}, saga_id: saga_id)

      assert_receive :spawned

      Dispatcher.dispatch(%TestEvent{value: :a, count: 1})

      assert_receive {:a, 1}

      Dispatcher.dispatch(%TestEvent{
        value: :c,
        count: 2
      })

      Dispatcher.dispatch(%TestEvent{
        value: :b,
        count: 1
      })

      assert_receive {:b, 1}

      Dispatcher.dispatch(%TestEvent{
        value: :c,
        count: 3
      })

      Dispatcher.dispatch(%TestEvent{
        value: :c,
        count: 3
      })

      assert_receive {:c, 3}

      assert_receive %Saga.Finish{saga_id: ^saga_id}
    end

    test "dispatches Saga.Started event after spawn/2" do
      saga_id = SagaID.new()
      Dispatcher.listen(Filter.new(fn %Saga.Finish{saga_id: ^saga_id} -> true end))
      Dispatcher.listen(Filter.new(fn %Saga.Started{saga_id: ^saga_id} -> true end))

      Saga.start_link(%TestAutomaton{pid: self()}, saga_id: saga_id)

      assert_receive :spawned

      refute_receive %Saga.Started{saga_id: ^saga_id}

      Dispatcher.dispatch(%TestEvent{
        value: :a,
        count: 1
      })

      assert_receive %Saga.Started{saga_id: ^saga_id}
    end

    test "dispatches Saga.Resumed event after respawn/2" do
      saga_id = SagaID.new()
      saga = %TestAutomaton{pid: self()}
      Dispatcher.listen(Filter.new(fn %Saga.Finish{saga_id: ^saga_id} -> true end))
      Dispatcher.listen(Filter.new(fn %Saga.Resumed{saga_id: ^saga_id} -> true end))

      Saga.resume(saga_id, saga, nil)

      assert_receive :respawned

      refute_receive %Saga.Resumed{saga_id: ^saga_id}

      Dispatcher.dispatch(%TestEvent{
        value: :a,
        count: 1
      })

      assert_receive %Saga.Resumed{saga_id: ^saga_id}
    end
  end

  describe "spawn/2 callback" do
    defmodule TestAutomatonNoSpawn do
      use Automaton

      defstruct [:pid]

      @impl true

      def yield(%__MODULE__{pid: pid}) do
        send(pid, :called)
        Automaton.finish()
      end
    end

    test "works with no spawn/2" do
      Saga.start_link(%TestAutomatonNoSpawn{pid: self()})

      assert_receive :called
    end
  end

  describe "yield/2 callback" do
    defmodule TestAutomatonNoYield do
      use Automaton

      defstruct [:pid]

      @impl true

      def spawn(%__MODULE__{pid: pid}) do
        send(pid, :called)
        Automaton.finish()
      end
    end

    test "works with no yield/2" do
      saga_id = SagaID.new()
      Dispatcher.listen(Filter.new(fn %Saga.Started{saga_id: ^saga_id} -> true end))
      Dispatcher.listen(Filter.new(fn %Saga.Finish{saga_id: ^saga_id} -> true end))

      Saga.start_link(%TestAutomatonNoYield{pid: self()}, saga_id: saga_id)

      assert_receive %Saga.Started{saga_id: ^saga_id}

      assert_receive :called

      assert_receive %Saga.Finish{saga_id: ^saga_id}
    end

    defmodule TestAutomatonFinishOnYield do
      use Automaton

      defstruct []

      @impl true
      def yield(%__MODULE__{}) do
        :next
      end

      def yield(:next) do
        Automaton.finish()
      end
    end

    test "finishes when yields Automaton.finish()" do
      saga_id = SagaID.new()
      Dispatcher.listen(Filter.new(fn %Saga.Finish{saga_id: ^saga_id} -> true end))

      Saga.start_link(%TestAutomatonFinishOnYield{}, saga_id: saga_id)

      assert_receive %Saga.Finish{saga_id: ^saga_id}
    end

    defmodule TestAutomatonCrash do
      use Automaton

      defstruct []

      @impl true

      def spawn(%__MODULE__{}) do
        raise "Crash!!!"
        Automaton.finish()
      end
    end

    test "dispatches Crashed event on crash" do
      TestHelper.surpress_crash_log()

      Dispatcher.listen_event_type(Saga.Crashed)

      saga_id = SagaID.new()
      Saga.start(%TestAutomatonCrash{}, saga_id: saga_id)

      assert_receive %Saga.Crashed{
        saga_id: ^saga_id,
        reason: %RuntimeError{},
        stacktrace: [{TestAutomatonCrash, _, _, _} | _]
      }
    end

    defmodule TestAutomatonQueue do
      use Automaton
      defstruct [:pid]

      @impl true
      def spawn(state) do
        perform(%Subscribe{
          event_filter: Filter.new(fn %TestEvent{} -> true end)
        })

        state
      end

      @impl true
      def yield(%__MODULE__{pid: pid}) do
        send(
          pid,
          perform(%Receive{
            event_filter: Filter.new(fn %TestEvent{value: :a} -> true end)
          })
        )

        send(
          pid,
          perform(%Receive{
            event_filter: Filter.new(fn %TestEvent{value: :c} -> true end)
          })
        )

        send(
          pid,
          perform(%Receive{
            event_filter: Filter.new(fn %TestEvent{value: :b} -> true end)
          })
        )

        Automaton.finish()
      end
    end

    test "stores ignored events in queue" do
      pid = self()

      Dispatcher.listen_event_type(Saga.Started)
      {:ok, saga_id} = Saga.start_link(%TestAutomatonQueue{pid: pid}, return: :saga_id)

      receive do
        %Saga.Started{saga_id: ^saga_id} -> :ok
      end

      Dispatcher.dispatch(%TestEvent{value: :a})
      Dispatcher.dispatch(%TestEvent{value: :b, extra: :first})
      Dispatcher.dispatch(%TestEvent{value: :b, extra: :second})
      Dispatcher.dispatch(%TestEvent{value: :c})

      assert_receive %TestEvent{value: :a}
      assert_receive %TestEvent{value: :b, extra: :first}
      assert_receive %TestEvent{value: :c}
    end

    defmodule TestAutomatonABC do
      use Automaton
      defstruct []

      @impl true
      def spawn(%__MODULE__{}) do
        perform(%Subscribe{
          event_filter: Filter.new(fn %TestEvent{} -> true end)
        })

        :a
      end

      @impl true
      def yield(:a) do
        perform(%Receive{})
        :b
      end

      @impl true
      def yield(:b) do
        perform(%Receive{})
        :c
      end

      @impl true
      def yield(:c) do
        perform(%Receive{})
        Automaton.finish()
      end
    end

    test "dispatches a Yield event on spawn" do
      saga_id = SagaID.new()

      Dispatcher.listen(
        Filter.new(fn %Automaton.Yield{saga_id: id} ->
          id == saga_id
        end)
      )

      Saga.start_link(%TestAutomatonABC{}, saga_id: saga_id)

      assert_receive %Automaton.Yield{
        state: :a
      }
    end

    test "dispatches a Yield event on yield" do
      saga_id = SagaID.new()

      Dispatcher.listen(
        Filter.new(fn %Automaton.Yield{saga_id: id} ->
          id == saga_id
        end)
      )

      Dispatcher.listen_event_type(Saga.Started)
      Saga.start_link(%TestAutomatonABC{}, saga_id: saga_id)

      receive do
        %Saga.Started{saga_id: ^saga_id} -> :ok
      end

      Dispatcher.dispatch(%TestEvent{})

      assert_receive %Automaton.Yield{
        state: :b
      }
    end
  end

  describe "respawn/3 callback" do
    defmodule TestAutomatonResume do
      use Automaton
      defstruct [:value]

      @impl true
      def spawn(saga) do
        Dispatcher.dispatch(%TestEvent{value: {:called_spawn, saga}})
        :a
      end

      @impl true
      def respawn(saga, state) do
        Dispatcher.dispatch(%TestEvent{value: {:called_respawn, saga, state}})
        state + 2
      end

      @impl true
      def yield(state) do
        perform(%Receive{})
        Dispatcher.dispatch(%TestEvent{value: {:called_yield, state}})
        state
      end
    end

    test "does not invoke spawn callback" do
      Dispatcher.listen_event_type(TestEvent)
      saga_id = SagaID.new()

      {:ok, _pid} =
        Saga.resume(
          saga_id,
          %TestAutomatonResume{},
          1
        )

      refute_receive %TestEvent{value: {:called_spawn, _}}
    end

    test "invokes respawn callback" do
      Dispatcher.listen_event_type(TestEvent)
      saga_id = SagaID.new()
      saga = %TestAutomatonResume{value: :some}

      {:ok, _pid} =
        Saga.resume(
          saga_id,
          saga,
          1
        )

      assert_receive %TestEvent{value: {:called_respawn, ^saga, 1}}
    end

    test "uses a respawn callback's result as the next state" do
      Dispatcher.listen_event_type(TestEvent)
      saga_id = SagaID.new()
      saga = %TestAutomatonResume{value: :some}

      {:ok, _pid} =
        Saga.resume(
          saga_id,
          saga,
          3
        )

      Saga.send_to(saga_id, %TestEvent{})

      assert_receive %TestEvent{value: {:called_yield, 5}}
    end

    test "dispatches Yield event on respawn" do
      saga_id = SagaID.new()
      saga = %TestAutomatonResume{value: :some}

      Dispatcher.listen(
        Filter.new(fn %Automaton.Yield{saga_id: id} ->
          id == saga_id
        end)
      )

      {:ok, _pid} =
        Saga.resume(
          saga_id,
          saga,
          3
        )

      assert_receive %Automaton.Yield{
        state: 5
      }
    end

    defmodule TestAutomatonFinishOnRespawn do
      use Automaton

      defstruct []

      @impl true
      def respawn(%__MODULE__{}, _state) do
        Automaton.finish()
      end

      @impl true
      def yield(_state), do: :ok
    end

    test "finishes when respawn/3 returns Automaton.finish()" do
      saga_id = SagaID.new()
      saga = %TestAutomatonFinishOnRespawn{}
      Dispatcher.listen(Filter.new(fn %Saga.Finish{saga_id: ^saga_id} -> true end))

      {:ok, _pid} =
        Saga.resume(
          saga_id,
          saga,
          3
        )

      assert_receive %Saga.Finish{saga_id: ^saga_id}
    end

    defmodule TestAutomatonNoRespawn do
      use Automaton

      defstruct []

      @impl true
      def spawn(%__MODULE__{}) do
        :spawn_state
      end

      @impl true
      def yield({:resume_state, pid}) do
        send(pid, :called)
        Automaton.finish()
      end
    end

    test "works with no respawn/2" do
      pid = self()
      saga_id = SagaID.new()
      saga = %TestAutomatonNoRespawn{}

      {:ok, _pid} =
        Saga.resume(
          saga_id,
          saga,
          {:resume_state, pid}
        )

      assert_receive :called
    end
  end
end
