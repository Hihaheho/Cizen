defmodule Cizen.Effects.EndTest do
  use Cizen.SagaCase
  alias Cizen.TestHelper

  alias Cizen.Effects.{End, Receive, Subscribe}
  alias Cizen.Filter
  alias Cizen.Saga

  require Filter

  defmodule(TestEvent, do: defstruct([:value]))

  describe "End" do
    test "ends a saga" do
      assert_handle(fn id ->
        saga_id = TestHelper.launch_test_saga()

        perform(id, %Subscribe{
          event_filter: Filter.new(fn %Saga.Ended{saga_id: ^saga_id} -> true end)
        })

        assert saga_id == perform(id, %End{saga_id: saga_id})

        perform(id, %Receive{
          event_filter: Filter.new(fn %Saga.Ended{saga_id: ^saga_id} -> true end)
        })
      end)
    end
  end
end
