defmodule Cizen.Dispatcher.NodeTest do
  use ExUnit.Case

  alias Cizen.Dispatcher.Node
  alias Cizen.Filter

  require Filter

  defmodule(TestEvent, do: defstruct([]))

  describe "put" do
    test "put true" do
      subscriber = self()
      {:ok, node} = Node.start_link()

      Node.put(node, true, subscriber)

      subscribers = MapSet.new([subscriber])

      assert %{
               operations: %{},
               subscribers: ^subscribers
             } = :sys.get_state(node)
    end

    test "put operation" do
      subscriber = self()
      {:ok, node} = Node.start_link()

      Node.put(node, {:<>, ["a", "b"]}, subscriber)

      assert %{
               {:<>, ["a", "b"]} => %{
                 true => next_node
               }
             } = :sys.get_state(node).operations

      assert :sys.get_state(next_node).subscribers == MapSet.new([subscriber])
    end

    test "put :==" do
      subscriber = self()
      {:ok, node} = Node.start_link()

      Node.put(node, {:==, [{:access, [:key]}, "a"]}, subscriber)

      assert %{
               {:access, [:key]} => %{
                 "a" => next_node
               }
             } = :sys.get_state(node).operations

      assert :sys.get_state(next_node).subscribers == MapSet.new([subscriber])
    end

    test "put not" do
      subscriber = self()
      {:ok, node} = Node.start_link()

      Node.put(node, {:not, [{:access, [:key]}]}, subscriber)

      assert %{
               {:access, [:key]} => %{
                 false => next_node
               }
             } = :sys.get_state(node).operations

      assert :sys.get_state(next_node).subscribers == MapSet.new([subscriber])
    end

    test "put and" do
      subscriber = self()
      {:ok, node} = Node.start_link()

      Node.put(node, {:and, ["a", {:and, ["b", "c"]}]}, subscriber)

      assert %{
               "a" => %{
                 true => second_node
               }
             } = :sys.get_state(node).operations

      assert %{
               "b" => %{
                 true => third_node
               }
             } = :sys.get_state(second_node).operations

      assert %{
               "c" => %{
                 true => forth_node
               }
             } = :sys.get_state(third_node).operations

      assert :sys.get_state(forth_node).subscribers == MapSet.new([subscriber])
    end

    test "put or" do
      subscriber = self()
      {:ok, node} = Node.start_link()

      Node.put(
        node,
        {:or, ["a", {:or, [{:==, [:exp, "b"]}, {:or, ["c", {:==, [:exp, "d"]}]}]}]},
        subscriber
      )

      assert %{
               "a" => %{
                 true => node1
               },
               "c" => %{
                 true => node2
               },
               :exp => %{
                 "b" => node3,
                 "d" => node4
               }
             } = :sys.get_state(node).operations

      assert :sys.get_state(node1).subscribers == MapSet.new([subscriber])
      assert :sys.get_state(node2).subscribers == MapSet.new([subscriber])
      assert :sys.get_state(node3).subscribers == MapSet.new([subscriber])
      assert :sys.get_state(node4).subscribers == MapSet.new([subscriber])
    end

    test "does not receive nothing after put :or" do
      subscriber = self()
      {:ok, node} = Node.start_link()

      %{code: code} = Filter.new(fn a -> a == "a" or a == "b" end)
      Node.put(node, code, subscriber)
      refute_receive _
    end

    test "removes assertion" do
      subscriber = self()
      {:ok, node} = Node.start_link()

      %{code: code} = Filter.new(fn %TestEvent{} -> true end)
      Node.put(node, code, subscriber)

      assert %{
               {:access, [:__struct__]} => %{
                 TestEvent => next_node
               }
             } = :sys.get_state(node).operations

      assert :sys.get_state(next_node).subscribers == MapSet.new([subscriber])
    end
  end

  test "deletes the subscriber from subscribers when it downed" do
    subscriber1 =
      spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

    subscriber2 = spawn_link(fn -> :timer.sleep(:infinity) end)

    {:ok, node} = Node.start_link()

    Node.put(node, true, subscriber1)
    Node.put(node, true, subscriber2)

    assert :sys.get_state(node).subscribers ==
             MapSet.new([subscriber1, subscriber2])

    :erlang.trace(node, true, [:receive])
    send(subscriber1, :stop)
    assert_receive {:trace, _, _, {:DOWN, _, _, ^subscriber1, _}}

    assert :sys.get_state(node).subscribers == MapSet.new([subscriber2])
  end

  test "deletes operation value when the next node downed" do
    subscriber =
      spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, node} = Node.start_link()
    %{code: code} = Filter.new(fn a -> a == "a" end)

    Node.put(node, code, subscriber)

    get_a_node = fn ->
      node
      |> :sys.get_state()
      |> get_in([:operations, {:access, []}, "a"])
    end

    assert not is_nil(get_a_node.())
    send(subscriber, :stop)
    :timer.sleep(100)
    assert is_nil(get_a_node.())
  end

  test "deletes operation when all operation value have deleted" do
    subscriber1 =
      spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

    subscriber2 =
      spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, node} = Node.start_link()
    %{code: code1} = Filter.new(fn a -> a == "a" end)
    %{code: code2} = Filter.new(fn a -> a == "b" end)
    Node.put(node, code1, subscriber1)
    Node.put(node, code2, subscriber2)

    get_operation = fn ->
      node
      |> :sys.get_state()
      |> get_in([:operations, {:access, []}])
    end

    assert %{} = get_operation.()

    send(subscriber1, :stop)
    :timer.sleep(50)
    assert %{} = get_operation.()

    send(subscriber2, :stop)
    :timer.sleep(50)
    assert nil == get_operation.()
  end

  test "exits when all subscribers have downed and operations is empty" do
    subscriber =
      spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, parent_node} = Node.start_link()
    {:ok, node} = Node.start_link(parent_node)
    Process.monitor(node)
    %{code: code} = Filter.new(fn a -> a == "a" end)
    Node.put(node, code, subscriber)

    send(subscriber, :stop)
    assert_receive {:DOWN, _, _, ^node, _}
    assert :ets.lookup(Node, node) == []
  end

  test "deletes a reference from parent node after exit" do
    subscriber =
      spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, parent_node} = Node.start_link()
    %{code: code} = Filter.new(fn a -> a == "a" end)
    Node.put(parent_node, code, subscriber)
    node = :sys.get_state(parent_node).operations[{:access, []}]["a"]
    Process.monitor(node)

    send(subscriber, :stop)

    receive do
      {:DOWN, _, _, ^node, _} -> :ok
    after
      1000 -> flunk()
    end

    assert :sys.get_state(parent_node).operations == %{}
  end

  test "does not exit if root even when all subscribers have downed and operations is empty" do
    subscriber =
      spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, node} = Node.start_link()
    Process.monitor(node)
    %{code: code} = Filter.new(fn a -> a == "a" end)
    Node.put(node, code, subscriber)

    send(subscriber, :stop)
    refute_receive {:DOWN, _, _, ^node, _}
  end

  test "pushes an event without raise right after node stops" do
    subscriber =
      spawn_link(fn ->
        receive do
          :stop -> :ok
        end
      end)

    {:ok, node} = Node.start_link()

    %{code: code} = Filter.new(fn a -> a == "a" end)

    Node.put(node, code, subscriber)

    for _ <- 0..100 do
      spawn_link(fn ->
        for _ <- 0..100 do
          Node.push(node, "a")
        end
      end)
    end

    spawn_link(fn ->
      send(subscriber, :stop)
    end)

    :timer.sleep(100)
  end

  test "puts a subscription without raise right after node stops" do
    for _ <- 0..5 do
      subscriber =
        spawn_link(fn ->
          receive do
            :stop -> :ok
          end
        end)

      {:ok, node} = Node.start_link()

      %{code: code} = Filter.new(fn a -> a == "a" end)
      Node.put(node, code, subscriber)

      for _ <- 0..100 do
        spawn_link(fn ->
          for _ <- 0..100 do
            Node.put(node, code, subscriber)
          end
        end)
      end

      spawn_link(fn ->
        send(subscriber, :stop)
      end)

      :timer.sleep(100)
    end
  end
end
