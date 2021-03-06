defmodule Cizen.Effects.EndTest do
  use Cizen.SagaCase
  alias Cizen.TestHelper
  import Cizen.TestHelper, only: [assert_condition: 2]

  alias Cizen.Effects.End
  alias Cizen.Pattern
  alias Cizen.Saga

  require Pattern

  defmodule(TestEvent, do: defstruct([:value]))

  describe "End" do
    test "ends a saga" do
      assert_handle(fn ->
        saga_id = TestHelper.launch_test_saga()

        assert saga_id == perform(%End{saga_id: saga_id})

        assert_condition(1000, :error = Saga.get_pid(saga_id))
      end)
    end
  end
end
