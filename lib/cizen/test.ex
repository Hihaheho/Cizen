defmodule Cizen.Test do
  @moduledoc """
  Conveniences for testing Cizen.
  """

  alias Cizen.Saga
  alias Cizen.SagaID

  defmacro __using__(_opts) do
    quote do
      use Cizen.Effectful
      import Cizen.Test
      import ExUnit.Callbacks, only: [setup: 1, on_exit: 1]

      setup do
        alias Cizen.Saga
        alias Cizen.{Dispatcher}
        alias Cizen.Test

        {:ok, agent} = Agent.start(fn -> [] end)

        pid = self()

        {:ok, task} =
          Task.start(fn ->
            Dispatcher.listen_event_type(Saga.Started)
            send(pid, :ok)

            for :ok <- Stream.cycle([:ok]) do
              receive do
                %Saga.Started{id: id} ->
                  Agent.update(agent, fn list -> [id | list] end)
              end
            end
          end)

        receive do
          :ok -> :ok
        end

        on_exit(fn ->
          sagas = Agent.get(agent, fn list -> list end)

          Enum.each(sagas, fn saga ->
            Test.ensure_finished(saga)
          end)

          Process.exit(task, :kill)
          Agent.stop(agent)
        end)

        :ok
      end
    end
  end

  @doc """
  Asserts that the block is finished in the given timeout.

  The default value of the timeout is 1000.
  """
  defmacro assert_handle(timeout \\ 2000, func) do
    quote bind_quoted: [timeout: timeout, func: func] do
      import Cizen.Effectful, only: [handle: 1]
      current = self()

      spawn_link(fn ->
        result = handle(func)
        send(current, {:finished, result})
      end)

      receive do
        {:finished, result} -> result
      after
        timeout -> flunk("timeout assert_handle")
      end
    end
  end

  @doc """
  Asserts that the effect is performed in the given timeout.

  The default value of the timeout is 100.
  """
  defmacro assert_perform(timeout \\ 100, id, effect) do
    quote bind_quoted: [timeout: timeout, id: id, effect: effect] do
      import Cizen.Automaton, only: [perform: 2]
      current = self()

      pid =
        spawn_link(fn ->
          result = perform id, effect
          send(current, {:finished, result})
        end)

      receive do
        resolved -> send(pid, resolved)
      after
        timeout -> flunk("timeout perform")
      end

      receive do
        {:finished, result} -> result
      after
        timeout -> flunk("timeout assert_perform")
      end
    end
  end

  @doc """
  Ensures the given saga is finished.
  """
  @spec ensure_finished(SagaID.t()) :: term
  def ensure_finished(id) do
    case Saga.get_pid(id) do
      {:ok, _pid} ->
        Saga.end_saga(id)

      _ ->
        :ok
    end
  end
end
