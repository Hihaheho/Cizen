defmodule Cizen.EffectfulTest do
  use Cizen.SagaCase

  alias Cizen.Dispatcher
  alias Cizen.Filter

  alias Cizen.Effects.{Dispatch}

  defmodule(TestEvent, do: defstruct([:value]))

  defmodule TestModule do
    use Cizen.Effectful

    def dispatch(body) do
      handle(fn ->
        perform %Dispatch{body: body}
      end)
    end

    def block do
      handle(fn ->
        # Block
        receive do
          _ -> :ok
        end
      end)
    end

    def return(value) do
      handle(fn ->
        value
      end)
    end
  end

  describe "handle/1" do
    test "handles effect" do
      Dispatcher.listen_event_type(TestEvent)

      spawn_link(fn ->
        TestModule.dispatch(%TestEvent{value: :somevalue})
      end)

      assert_receive %TestEvent{value: :somevalue}
    end

    test "blocks the current thread" do
      spawn_link(fn ->
        TestModule.block()
        flunk("called")
      end)

      :timer.sleep(10)
    end

    test "returns the last expression" do
      assert :somevalue == TestModule.return(:somevalue)
    end

    test "works with other messages" do
      pid = self()
      filter = Filter.new(fn %TestEvent{value: a} -> a == 1 end)

      task =
        Task.async(fn ->
          send(
            pid,
            handle(fn ->
              perform(%Subscribe{
                event_filter: filter
              })

              send(pid, :subscribed)

              perform(%Receive{
                event_filter: filter
              })
            end)
          )
        end)

      receive do
        :subscribed -> :ok
      end

      send(task.pid, %TestEvent{value: 2})
      Dispatcher.dispatch(%TestEvent{value: 1})
      assert %TestEvent{value: 1} = Task.await(task)
    end
  end
end
