defmodule Cizen.TestHelper do
  @moduledoc false
  import ExUnit.Assertions, only: [flunk: 0]

  alias Cizen.{Dispatcher, Filter}
  alias Cizen.Saga
  alias Cizen.SagaID
  alias Cizen.TestSaga

  require Filter

  def launch_test_saga(opts \\ []) do
    saga_id = SagaID.new()
    pid = self()

    task =
      Task.async(fn ->
        Dispatcher.listen(Filter.new(fn %Saga.Started{saga_id: ^saga_id} -> true end))

        Saga.start_saga(
          saga_id,
          %TestSaga{
            init: fn id, state ->
              init = Keyword.get(opts, :init, fn _id, state -> state end)
              state = init.(id, state)
              state
            end,
            handle_event: Keyword.get(opts, :handle_event, fn _id, _event, state -> state end),
            extra: Keyword.get(opts, :extra, nil)
          },
          pid
        )

        receive do
          %Saga.Started{} -> :ok
        after
          1000 -> flunk()
        end
      end)

    Task.await(task)

    saga_id
  end

  defmacro assert_condition(timeout, assertion) do
    quote do
      func = fn
        func, 1 ->
          assert unquote(assertion)

        func, count ->
          unless unquote(assertion) do
            :timer.sleep(1)
            func.(func, count - 1)
          end
      end

      func.(func, unquote(timeout))
    end
  end

  defmodule CrashLogSurpressor do
    @moduledoc false
    use Cizen.Automaton

    alias Cizen.Effects.Receive

    defstruct []

    def spawn(_id, %__MODULE__{}) do
      :loop
    end

    def yield(id, :loop) do
      perform(id, %Receive{})

      :loop
    end
  end

  def surpress_crash_log do
    Saga.fork(%CrashLogSurpressor{})
  end
end
