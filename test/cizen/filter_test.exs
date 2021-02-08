defmodule Cizen.FilterTest do
  use ExUnit.Case

  alias Cizen.Filter
  require Cizen.Filter

  defmodule(A, do: defstruct([:key1, :key2]))
  defmodule(B, do: defstruct([:key1, :key2, :a]))
  defmodule(C, do: defstruct([:key1, :key2, :b]))

  test "throw exception on a wrong struct destructure" do
    assert_raise CompileError, fn ->
      quoted =
        quote do
          Filter.new(fn %A{key1: a, key2: b, key3: c} ->
            a + b + c == 3
          end)
        end

      Code.eval_quoted(quoted, [], __ENV__)
    end
  end

  test "checks type" do
    filter = Filter.new(fn %A{key1: a} -> a == "a" end)
    assert Filter.match?(filter, %A{key1: "a"})
    refute Filter.match?(filter, %B{key1: "a"})
  end

  test "all/1" do
    filter_3 = Filter.new(fn %A{key1: a} -> rem(a, 3) == 0 end)
    filter_5 = Filter.new(fn %A{key1: a} -> rem(a, 5) == 0 end)
    filter = Filter.all([filter_3, filter_5])
    assert Filter.match?(filter, %A{key1: 15})
    refute Filter.match?(filter, %A{key1: 5})
    refute Filter.match?(filter, %A{key1: 3})
    refute Filter.match?(filter, %A{key1: 1})
  end

  test "all/1 with an empty list" do
    filter = Filter.all([])
    assert Filter.match?(filter, %A{})
    assert Filter.match?(filter, nil)
  end

  test "any/1" do
    filter_3 = Filter.new(fn %A{key1: a} -> rem(a, 3) == 0 end)
    filter_5 = Filter.new(fn %A{key1: a} -> rem(a, 5) == 0 end)
    filter = Filter.any([filter_3, filter_5])
    assert Filter.match?(filter, %A{key1: 15})
    assert Filter.match?(filter, %A{key1: 5})
    assert Filter.match?(filter, %A{key1: 3})
    refute Filter.match?(filter, %A{key1: 1})
  end

  test "any/1 with an empty list" do
    filter = Filter.any([])
    refute Filter.match?(filter, %A{})
    refute Filter.match?(filter, true)
  end

  test "eval value" do
    assert Filter.eval("a", %A{}) == "a"
  end

  test "eval access" do
    filter =
      Filter.new(fn %C{b: %B{a: %A{key2: c}}} ->
        c
      end)

    assert Filter.eval(filter.code, %C{b: %B{a: %A{key2: "a"}}}) == "a"
  end

  test "eval access to nil value" do
    filter =
      Filter.new(fn %C{b: %B{a: %A{key2: c}}} ->
        c == "c"
      end)

    assert Filter.eval(filter.code, %C{b: %B{a: nil}}) == false
  end

  test "eval root access" do
    filter =
      Filter.new(fn a ->
        a
      end)

    assert Filter.eval(filter.code, %A{key1: "a"}) == %A{key1: "a"}
  end

  test "eval call" do
    filter =
      Filter.new(fn %A{key1: a} ->
        Enum.count(a)
      end)

    assert Filter.eval(filter.code, %A{key1: [1, 2, 3]}) == 3
  end

  test "eval is_nil" do
    filter =
      Filter.new(fn %A{key1: a} ->
        is_nil(a)
      end)

    assert Filter.eval(filter.code, %A{key1: :a}) == false
    assert Filter.eval(filter.code, %A{key1: nil}) == true
  end

  test "eval to_string" do
    filter =
      Filter.new(fn %A{key1: a} ->
        to_string(a)
      end)

    assert Filter.eval(filter.code, %A{key1: :atom}) == "atom"
  end

  test "eval to_charlist" do
    filter =
      Filter.new(fn %A{key1: a} ->
        to_charlist(a)
      end)

    assert Filter.eval(filter.code, %A{key1: :atom}) == 'atom'
  end

  test "eval not" do
    filter =
      Filter.new(fn %A{key1: a} ->
        not a
      end)

    assert Filter.eval(filter.code, %A{key1: true}) == false
    assert Filter.eval(filter.code, %A{key1: false}) == true
  end

  test "eval !" do
    filter =
      Filter.new(fn %A{key1: a} ->
        !a
      end)

    assert Filter.eval(filter.code, %A{key1: "a"}) == false
    assert Filter.eval(filter.code, %A{key1: nil}) == true
  end

  test "eval and" do
    filter =
      Filter.new(fn %A{key1: a, key2: b} ->
        a and b
      end)

    assert Filter.eval(filter.code, %A{key1: true, key2: true}) == true
    assert Filter.eval(filter.code, %A{key1: true, key2: false}) == false
    assert Filter.eval(filter.code, %A{key1: false, key2: true}) == false
    assert Filter.eval(filter.code, %A{key1: false, key2: false}) == false
  end

  test "eval &&" do
    filter =
      Filter.new(fn %A{key1: a, key2: b} ->
        a && b
      end)

    assert Filter.eval(filter.code, %A{key1: "a", key2: "b"}) == "b"
    assert Filter.eval(filter.code, %A{key1: nil, key2: "b"}) == nil
  end

  test "eval or" do
    filter =
      Filter.new(fn %A{key1: a, key2: b} ->
        a or b
      end)

    assert Filter.eval(filter.code, %A{key1: true, key2: true}) == true
    assert Filter.eval(filter.code, %A{key1: true, key2: false}) == true
    assert Filter.eval(filter.code, %A{key1: false, key2: true}) == true
    assert Filter.eval(filter.code, %A{key1: false, key2: false}) == false
  end

  test "eval ||" do
    filter =
      Filter.new(fn %A{key1: a, key2: b} ->
        a || b
      end)

    assert Filter.eval(filter.code, %A{key1: "a", key2: "b"}) == "a"
    assert Filter.eval(filter.code, %A{key1: nil, key2: "b"}) == "b"
  end

  test "eval in" do
    filter =
      Filter.new(fn %A{key1: a, key2: b} ->
        a in b
      end)

    assert Filter.eval(filter.code, %A{key1: 1, key2: [1, 2]}) == true
    assert Filter.eval(filter.code, %A{key1: 3, key2: [1, 2]}) == false
  end

  test "eval .." do
    filter =
      Filter.new(fn %A{key1: a, key2: b} ->
        a..b
      end)

    assert Filter.eval(filter.code, %A{key1: 1, key2: 10}) == 1..10
  end

  test "eval <>" do
    filter =
      Filter.new(fn %A{key1: a, key2: b} ->
        a <> b
      end)

    assert Filter.eval(filter.code, %A{key1: "a", key2: "b"}) == "ab"
  end

  test "eval operators" do
    filter =
      Filter.new(fn %A{key1: a} ->
        a * 2 == 42
      end)

    assert Filter.eval(filter.code, %A{key1: 21}) == true
    assert Filter.eval(filter.code, %A{key1: 1}) == false

    filter =
      Filter.new(fn %A{key1: a} ->
        -a
      end)

    assert Filter.eval(filter.code, %A{key1: 3}) == -3

    filter =
      Filter.new(fn %A{key1: a, key2: b} ->
        a && b
      end)

    assert Filter.eval(filter.code, %A{key1: "a", key2: "b"}) == "b"
  end

  test "multiple cases" do
    filter =
      Filter.new(fn
        %A{key1: a} -> a == "value"
        %B{key1: b} -> b == "value"
      end)

    assert Filter.eval(filter.code, %A{key1: "value"}) == true
    assert Filter.eval(filter.code, %B{key1: "value"}) == true
    refute Filter.eval(filter.code, %C{key1: "value"}) == true
    refute Filter.eval(filter.code, %A{key1: "another value"}) == true
  end

  test "multiple cases with a negative case" do
    filter =
      Filter.new(fn
        %A{key1: 0} -> false
        %A{key1: value} -> rem(value, 2) == 0
      end)

    refute Filter.eval(filter.code, %A{key1: 0})
    assert Filter.eval(filter.code, %A{key1: 2})
    refute Filter.eval(filter.code, %A{key1: 1})
    assert Filter.eval(filter.code, %A{key1: 4})
  end

  test "guard" do
    filter =
      Filter.new(fn
        %A{key1: a, key2: b} when a in [:a, :b, :c] and not is_nil(b) -> false
        %A{key1: a} when a in [:a, :b, :c] -> true
      end)

    assert Filter.eval(filter.code, %A{key1: :a, key2: nil})
    refute Filter.eval(filter.code, %A{key1: :a, key2: :a})
    assert Filter.eval(filter.code, %A{key1: :a})
    refute Filter.eval(filter.code, %A{key1: :d})
  end
end
