defmodule Cizen.CrashLoggerTest do
  use Cizen.SagaCase, async: false
  import ExUnit.CaptureLog
  alias Cizen.TestHelper

  alias Cizen.Dispatcher
  alias Cizen.Pattern

  require Pattern

  defmodule(CrashTestEvent, do: defstruct([]))

  test "logs crashes" do
    saga_id =
      TestHelper.launch_test_saga(
        on_start: fn _state ->
          Dispatcher.listen_event_type(CrashTestEvent)
        end,
        handle_event: fn body, state ->
          case body do
            %CrashTestEvent{} ->
              raise "Crash!!!"

            _ ->
              state
          end
        end
      )

    output =
      capture_log(fn ->
        Dispatcher.dispatch(%CrashTestEvent{})
        :timer.sleep(100)
        require Logger
        Logger.flush()
      end)

    IO.puts(output)

    assert output =~ "saga #{saga_id} is crashed"
    assert output =~ "%Cizen.TestSaga{"
    assert output =~ "(RuntimeError) Crash!!!"
    assert output =~ "test/cizen/crash_logger_test.exs:"
  end
end
