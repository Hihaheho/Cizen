defmodule Cizen.SagaRegistryTest do
  use Cizen.SagaCase
  alias Cizen.Test
  alias Cizen.TestHelper

  alias Cizen.Saga
  alias Cizen.SagaID
  alias Cizen.SagaRegistry

  defp setup_registry(_context) do
    SagaRegistry.start_link(keys: :unique, name: __MODULE__)
    :ok
  end

  describe "register/4" do
    setup [:setup_registry]

    test "registers the given key-value" do
      id = TestHelper.launch_test_saga()
      assert {:ok, _} = SagaRegistry.register(__MODULE__, id, :a, :value_a)
      {:ok, pid} = Saga.get_pid(id)
      assert [{pid, {id, :value_a}}] == Registry.lookup(__MODULE__, :a)
    end

    test "remove the entry on finish" do
      id = TestHelper.launch_test_saga()
      assert {:ok, _} = SagaRegistry.register(__MODULE__, id, :a, :value_a)
      Test.ensure_finished(id)
      :timer.sleep(1)
      assert [] == Registry.lookup(__MODULE__, :a)
    end

    test "returns error if the saga does not exists" do
      id = SagaID.new()
      assert {:error, :no_saga} == SagaRegistry.register(__MODULE__, id, :a, :value_a)
    end

    test "returns error if already registered" do
      saga_a = TestHelper.launch_test_saga()
      saga_b = TestHelper.launch_test_saga()
      assert {:ok, _} = SagaRegistry.register(__MODULE__, saga_a, :a, :value_a)

      assert {:error, {:already_registered, saga_a}} ==
               SagaRegistry.register(__MODULE__, saga_b, :a, :c)
    end

    test "doesn't deadlock in Saga" do
      pid = self()

      TestHelper.launch_test_saga(
        on_start: fn _ ->
          id = Saga.self()
          SagaRegistry.register(__MODULE__, id, :a, :value_a)
          send(pid, :registered)
        end
      )

      assert_receive :registered
    end
  end

  defp setup_registered(_context) do
    saga_a = TestHelper.launch_test_saga()
    saga_b = TestHelper.launch_test_saga()
    {:ok, _} = SagaRegistry.register(__MODULE__, saga_a, :a, :value_a)
    {:ok, _} = SagaRegistry.register(__MODULE__, saga_b, :b, :value_b)
    %{saga_a: saga_a, saga_b: saga_b}
  end

  describe "dispatch/4" do
    setup [:setup_registry, :setup_registered]

    defmodule TestDispatcher do
      def dispatch(entries, pid) do
        for entry <- entries do
          send(pid, entry)
        end
      end
    end

    test "works with a callback", %{saga_a: saga_a} do
      pid = self()

      SagaRegistry.dispatch(__MODULE__, :a, fn entries ->
        for entry <- entries do
          send(pid, entry)
        end
      end)

      assert_receive {^saga_a, :value_a}
    end

    test "works with {module, function, arguments}", %{saga_a: saga_a} do
      pid = self()
      SagaRegistry.dispatch(__MODULE__, :a, {TestDispatcher, :dispatch, [pid]})
      assert_receive {^saga_a, :value_a}
    end
  end

  describe "lookup/2" do
    setup [:setup_registry, :setup_registered]

    test "works", %{saga_a: saga_a} do
      assert [{saga_a, :value_a}] == SagaRegistry.lookup(__MODULE__, :a)
    end
  end

  describe "unregister/3" do
    setup [:setup_registry, :setup_registered]

    test "works", %{saga_a: saga_a} do
      SagaRegistry.unregister(__MODULE__, saga_a, :a)
      assert 1 == SagaRegistry.count(__MODULE__)
    end

    test "doesn't deadlock in Saga" do
      pid = self()

      TestHelper.launch_test_saga(
        on_start: fn _ ->
          id = Saga.self()
          SagaRegistry.register(__MODULE__, id, :c, :value_c)
          SagaRegistry.unregister(__MODULE__, id, :c)
          send(pid, :unregistered)
        end
      )

      assert_receive :unregistered
      assert 2 == SagaRegistry.count(__MODULE__)
    end
  end

  describe "update_value/4" do
    setup [:setup_registry, :setup_registered]

    test "works", %{saga_a: saga_a} do
      SagaRegistry.update_value(__MODULE__, saga_a, :a, fn value -> {:changed, value} end)
      assert [{saga_a, {:changed, :value_a}}] == SagaRegistry.lookup(__MODULE__, :a)
    end

    test "doesn't deadlock in Saga" do
      pid = self()

      id =
        TestHelper.launch_test_saga(
          on_start: fn _ ->
            id = Saga.self()
            SagaRegistry.register(__MODULE__, id, :c, 1)
            SagaRegistry.update_value(__MODULE__, id, :c, fn value -> value + 1 end)
            send(pid, :updated)
          end
        )

      assert_receive :updated
      assert [{id, 2}] == SagaRegistry.lookup(__MODULE__, :c)
    end
  end

  describe "keys/2" do
    setup [:setup_registry, :setup_registered]

    test "works", %{saga_a: saga_a, saga_b: saga_b} do
      {:ok, _} = SagaRegistry.register(__MODULE__, saga_b, :b2, :value_b2)

      assert [:a] == SagaRegistry.keys(__MODULE__, saga_a)

      b_keys = SagaRegistry.keys(__MODULE__, saga_b)
      assert length(b_keys)
      assert :b in b_keys
      assert :b2 in b_keys
    end

    test "returns empty for an unknown saga ID" do
      assert [] == SagaRegistry.keys(__MODULE__, SagaID.new())
    end
  end
end
