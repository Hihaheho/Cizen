defmodule Pattern.CodeTest do
  use ExUnit.Case

  alias Cizen.Pattern
  require Pattern
  import Pattern.Code, only: [as_code: 2, and_: 2, or_: 2, access_: 1, call_: 3, op_: 2]

  defmodule(A, do: defstruct([:key1, :key2, :b]))
  defmodule(B, do: defstruct([:key1, :key2, :a]))
  defmodule(C, do: defstruct([:key1, :key2, :b]))

  test "creates a pattern with is_nil" do
    pattern =
      Pattern.new(fn %A{key1: a} ->
        is_nil(a)
      end)

    assert and_(
             and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
             op_(:is_nil, [access_([:key1])])
           ) == pattern.code
  end

  test "creates a pattern with to_string" do
    pattern =
      Pattern.new(fn %A{key1: a} ->
        to_string(a)
      end)

    assert and_(
             and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
             op_(:to_string, [access_([:key1])])
           ) == pattern.code
  end

  test "creates a pattern with to_charlist" do
    pattern =
      Pattern.new(fn %A{key1: a} ->
        to_charlist(a)
      end)

    assert and_(
             and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
             op_(:to_charlist, [access_([:key1])])
           ) == pattern.code
  end

  test "creates a pattern with arguments" do
    value1 = "value1"
    pattern = Pattern.new(fn %A{key1: a} -> a == value1 end)

    assert and_(
             and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
             op_(:==, [access_([:key1]), "value1"])
           ) == pattern.code
  end

  test "nested struct" do
    pattern =
      Pattern.new(fn %C{key1: a, b: %B{key1: b, a: %A{key2: c}}} ->
        a == "a" and b == "b" and c == "c"
      end)

    expected =
      and_(
        and_(
          and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), C])),
          and_(
            and_(op_(:is_map, [access_([:b])]), op_(:==, [access_([:b, :__struct__]), B])),
            and_(op_(:is_map, [access_([:b, :a])]), op_(:==, [access_([:b, :a, :__struct__]), A]))
          )
        ),
        and_(
          and_(
            op_(:==, [access_([:key1]), "a"]),
            op_(:==, [access_([:b, :key1]), "b"])
          ),
          op_(:==, [access_([:b, :a, :key2]), "c"])
        )
      )

    assert expected == pattern.code
  end

  test "embedded pattern" do
    b_pattern =
      Pattern.new(fn %B{key1: a, a: %A{key2: b}} ->
        a == "b" and b == "c"
      end)

    pattern =
      Pattern.new(fn %C{key1: a, b: b} ->
        a == "a" and Pattern.match?(b_pattern, b)
      end)

    assert and_(
             and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), C])),
             and_(
               op_(:==, [access_([:key1]), "a"]),
               and_(
                 and_(
                   and_(op_(:is_map, [access_([:b])]), op_(:==, [access_([:b, :__struct__]), B])),
                   and_(
                     op_(:is_map, [access_([:b, :a])]),
                     op_(:==, [access_([:b, :a, :__struct__]), A])
                   )
                 ),
                 and_(
                   op_(:==, [access_([:b, :key1]), "b"]),
                   op_(:==, [access_([:b, :a, :key2]), "c"])
                 )
               )
             )
           ) == pattern.code
  end

  test "embedded Pattern.new" do
    pattern =
      Pattern.new(fn %C{key1: a, b: b} ->
        a == "a" and
          Pattern.match?(
            Pattern.new(fn %B{key1: a, a: %A{key2: b}} ->
              a == "b" and b == "c"
            end),
            b
          )
      end)

    assert and_(
             and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), C])),
             and_(
               op_(:==, [access_([:key1]), "a"]),
               and_(
                 and_(
                   and_(op_(:is_map, [access_([:b])]), op_(:==, [access_([:b, :__struct__]), B])),
                   and_(
                     op_(:is_map, [access_([:b, :a])]),
                     op_(:==, [access_([:b, :a, :__struct__]), A])
                   )
                 ),
                 and_(
                   op_(:==, [access_([:b, :key1]), "b"]),
                   op_(:==, [access_([:b, :a, :key2]), "c"])
                 )
               )
             )
           ) == pattern.code
  end

  defmodule TestModule do
    def func(a, b), do: {a, b}
  end

  test "transforms module function calls" do
    c = "c"

    pattern =
      Pattern.new(fn %A{key1: a, key2: b} ->
        TestModule.func(c, "d") == TestModule.func(a, b)
      end)

    assert and_(
             and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
             {
               :==,
               [
                 {"c", "d"},
                 call_(TestModule, :func, [access_([:key1]), access_([:key2])])
               ]
             }
           ) == pattern.code
  end

  test "transforms local function calls" do
    defmodule TestLocalFunctionModule do
      def local_function(a, b), do: {a, b}

      def pattern do
        c = "c"

        Pattern.new(fn %A{key1: a, key2: b} ->
          local_function(local_function(a, "a"), b) == local_function(c, "d")
        end)
      end
    end

    assert and_(
             and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
             op_(
               :==,
               [
                 call_(TestLocalFunctionModule, :local_function, [
                   call_(TestLocalFunctionModule, :local_function, [access_([:key1]), "a"]),
                   access_([:key2])
                 ]),
                 {"c", "d"}
               ]
             )
           ) == TestLocalFunctionModule.pattern().code
  end

  test "transforms imported function calls" do
    c = "c"

    import TestModule

    pattern =
      Pattern.new(fn %A{key1: a, key2: b} ->
        func(func(a, "a"), b) == func(c, "d")
      end)

    assert {
             :and,
             [
               and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
               op_(
                 :==,
                 [
                   call_(TestModule, :func, [
                     call_(TestModule, :func, [access_([:key1]), "a"]),
                     access_([:key2])
                   ]),
                   {"c", "d"}
                 ]
               )
             ]
           } == pattern.code
  end

  def test_fun(a, b, c, d, e), do: {a, b, c, d, e}

  test "use = in argument" do
    pattern =
      Pattern.new(fn %C{key1: a, b: %B{key1: b, a: %A{key2: c} = d}} = e ->
        test_fun(a, b, c, d, e)
      end)

    expected =
      and_(
        and_(
          and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), C])),
          and_(
            and_(op_(:is_map, [access_([:b])]), op_(:==, [access_([:b, :__struct__]), B])),
            and_(op_(:is_map, [access_([:b, :a])]), op_(:==, [access_([:b, :a, :__struct__]), A]))
          )
        ),
        call_(__MODULE__, :test_fun, [
          access_([:key1]),
          access_([:b, :key1]),
          access_([:b, :a, :key2]),
          access_([:b, :a]),
          access_([])
        ])
      )

    assert expected == pattern.code
  end

  test "all/1" do
    a = access_([:a])
    b = access_([:b])
    c = access_([:c])
    code = Pattern.Code.all([a, b, c])
    assert and_(a, and_(b, c)) == code
  end

  test "all/1 with one" do
    a = access_([:a])
    code = Pattern.Code.all([a])
    assert a == code
  end

  test "all/1 with empty list" do
    code = Pattern.Code.all([])
    assert true == code
  end

  test "any/1" do
    a = access_([:a])
    b = access_([:b])
    c = access_([:c])
    code = Pattern.Code.any([a, b, c])
    assert or_(a, or_(b, c)) == code
  end

  test "any/1 with one" do
    a = access_([:a])
    code = Pattern.Code.any([a])
    assert a == code
  end

  test "any/1 with empty list" do
    code = Pattern.Code.any([])
    assert false == code
  end

  test "access fields with . operator" do
    pattern =
      Pattern.new(fn struct ->
        struct.key1.key2.key3
      end)

    assert access_([:key1, :key2, :key3]) == pattern.code
  end

  test "access fields with [] operator" do
    key2 = :key2

    pattern =
      Pattern.new(fn struct ->
        struct[:key1][key2][:key3]
      end)

    assert access_([:key1, :key2, :key3]) == pattern.code
  end

  test "access fields with both of . and []" do
    pattern =
      Pattern.new(fn struct ->
        struct.key1[:key2].key3 == struct[:key1].key2[:key3]
      end)

    assert op_(
             :==,
             [
               access_([:key1, :key2, :key3]),
               access_([:key1, :key2, :key3])
             ]
           ) == pattern.code
  end

  test "inline operators" do
    value = "a"

    pattern =
      Pattern.new(fn %A{key1: _} ->
        is_nil(value) or true
      end)

    assert and_(
             and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
             true
           ) == pattern.code
  end

  test "value in match" do
    pattern = Pattern.new(fn %A{key1: 3, key2: %B{key1: 5}} -> true end)

    expected =
      and_(
        and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
        and_(
          op_(:==, [access_([:key1]), 3]),
          and_(
            and_(op_(:is_map, [access_([:key2])]), op_(:==, [access_([:key2, :__struct__]), B])),
            op_(:==, [access_([:key2, :key1]), 5])
          )
        )
      )

    assert expected == pattern.code
  end

  test "match with pin operator" do
    a = 3
    b = 5
    pattern = Pattern.new(fn %A{key1: ^a, key2: %B{key1: ^b}} -> true end)

    expected =
      and_(
        and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
        and_(
          op_(:==, [access_([:key1]), 3]),
          and_(
            and_(op_(:is_map, [access_([:key2])]), op_(:==, [access_([:key2, :__struct__]), B])),
            op_(:==, [access_([:key2, :key1]), 5])
          )
        )
      )

    assert expected == pattern.code
  end

  test "match with same values" do
    pattern = Pattern.new(fn %A{key1: a, key2: a, b: %B{key1: a}} -> true end)

    expected =
      and_(
        and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
        and_(
          op_(:==, [access_([:key2]), access_([:key1])]),
          and_(
            and_(op_(:is_map, [access_([:b])]), op_(:==, [access_([:b, :__struct__]), B])),
            op_(:==, [access_([:b, :key1]), access_([:key1])])
          )
        )
      )

    assert expected == pattern.code
  end

  describe "as_code(args, do: block)" do
    test "translates the block into a code" do
      binded = 3

      code =
        as_code value: {:access, [:key1, :key2]} do
          value.key3 == binded
        end

      expected = op_(:==, [access_([:key1, :key2, :key3]), 3])

      assert code == expected
    end
  end
end
