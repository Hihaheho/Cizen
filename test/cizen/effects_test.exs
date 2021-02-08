defmodule Cizen.EffectsTest do
  use ExUnit.Case

  test "aliases all effects" do
    use Cizen.Effects
    assert Code.ensure_loaded?(All)
    assert Code.ensure_loaded?(Chain)
    assert Code.ensure_loaded?(Dispatch)
    assert Code.ensure_loaded?(End)
    assert Code.ensure_loaded?(Fork)
    assert Code.ensure_loaded?(Race)
    assert Code.ensure_loaded?(Receive)
    assert Code.ensure_loaded?(Start)
    assert Code.ensure_loaded?(Subscribe)

    Code.compile_quoted(
      quote do
        %Map{effect: %Receive{}, transform: fn x -> x end}
      end
    )
  end

  test "aliases only specified effects" do
    use Cizen.Effects, only: [Chain, Dispatch, End, Receive]
    refute Code.ensure_loaded?(All)
    assert Code.ensure_loaded?(Chain)
    assert Code.ensure_loaded?(Dispatch)
    assert Code.ensure_loaded?(End)
    refute Code.ensure_loaded?(Fork)
    refute Code.ensure_loaded?(Race)
    assert Code.ensure_loaded?(Receive)
    refute Code.ensure_loaded?(Start)
    refute Code.ensure_loaded?(Subscribe)

    assert_raise CompileError, fn ->
      Code.compile_quoted(
        quote do
          %Map{effect: %Receive{}, transform: fn x -> x end}
        end
      )
    end
  end

  test "Elixir.Map's interfaces are available when use Cizen.Effects" do
    use Cizen.Effects
    %Map{effect: %Receive{}, transform: fn x -> x end}
    assert 1 == Map.get(%{a: 1}, :a)
    assert %{a: :a, b: :b} == Map.put(%{a: :a}, :b, :b)
  end
end
