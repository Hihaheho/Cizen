defmodule Pattern.CompilerTest do
  use ExUnit.Case

  alias Cizen.Pattern
  require Pattern
  import Pattern.Code, only: [and_: 2, or_: 2, not_: 1, access_: 1, call_: 3, op_: 2]
  alias Pattern.Compiler

  defmodule(A, do: defstruct([:key1, :key2]))
  defmodule(B, do: defstruct([:key1, :key2]))
  defmodule(C, do: defstruct([:key1]))

  test "create pattern without :__block__" do
    pattern =
      Pattern.new(fn %A{key1: a} ->
        not a
      end)

    assert and_(
             and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
             not_(access_([:key1]))
           ) == pattern.code
  end

  test "support multiple cases" do
    pattern =
      Pattern.new(fn
        %A{key1: a} ->
          a == "a"

        %B{key1: a, key2: "b"} ->
          call(a)

        %C{key1: a} ->
          call(a)
      end)

    expected =
      or_(
        and_(
          and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
          op_(:==, [access_([:key1]), "a"])
        ),
        or_(
          and_(
            and_(
              not_(and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A]))),
              and_(
                and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), B])),
                op_(:==, [access_([:key2]), "b"])
              )
            ),
            call_(__MODULE__, :call, [access_([:key1])])
          ),
          and_(
            and_(
              not_(and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A]))),
              and_(
                not_(
                  and_(
                    and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), B])),
                    op_(:==, [access_([:key2]), "b"])
                  )
                ),
                and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), C]))
              )
            ),
            call_(__MODULE__, :call, [access_([:key1])])
          )
        )
      )

    assert expected == pattern.code
  end

  test "support when guard" do
    pattern =
      Pattern.new(fn
        %A{key1: a, key2: b} when is_nil(a) and not is_nil(b) -> "a"
        %A{key1: a} when a in [:a, :b, :c] -> "b"
      end)

    expected =
      or_(
        and_(
          and_(
            and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
            and_(
              op_(:is_nil, [access_([:key1])]),
              not_(op_(:is_nil, [access_([:key2])]))
            )
          ),
          "a"
        ),
        and_(
          and_(
            not_(
              and_(
                and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
                and_(
                  op_(:is_nil, [access_([:key1])]),
                  not_(op_(:is_nil, [access_([:key2])]))
                )
              )
            ),
            and_(
              and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
              op_(:in, [access_([:key1]), [:a, :b, :c]])
            )
          ),
          "b"
        )
      )

    assert expected == pattern.code
  end

  test "support pattern style with guard" do
    actual = Pattern.new(%A{key1: 3, key2: %B{key1: a}} when is_integer(a))
    filter = Pattern.new(fn %A{key1: 3, key2: %B{key1: a}} when is_integer(a) -> true end)

    assert actual == filter
  end

  test "support pattern style with no guard" do
    actual = Pattern.new(%A{key1: 3, key2: %B{key1: :value}})
    filter = Pattern.new(fn %A{key1: 3, key2: %B{key1: :value}} -> true end)

    assert actual == filter
  end

  describe "support map" do
    test "in filter style" do
      pattern = Pattern.new(fn %{key1: :a} -> true end)

      assert pattern.code ==
               and_(
                 op_(:is_map, [access_([])]),
                 and_(
                   call_(Map, :has_key?, [access_([]), :key1]),
                   op_(:==, [access_([:key1]), :a])
                 )
               )
    end

    test "in filter style with binding" do
      pattern = Pattern.new(fn %{} = b -> b.key1 == :a end)

      assert pattern.code == and_(op_(:is_map, [access_([])]), op_(:==, [access_([:key1]), :a]))
    end

    test "in pattern style" do
      pattern = Pattern.new(%{key1: :a})

      assert pattern.code ==
               and_(
                 op_(:is_map, [access_([])]),
                 and_(
                   call_(Map, :has_key?, [access_([]), :key1]),
                   op_(:==, [access_([:key1]), :a])
                 )
               )
    end

    test "with string key" do
      pattern = Pattern.new(%{"key1" => :a})

      assert pattern.code ==
               and_(
                 op_(:is_map, [access_([])]),
                 and_(
                   call_(Map, :has_key?, [access_([]), "key1"]),
                   op_(:==, [access_(["key1"]), :a])
                 )
               )
    end
  end

  describe "to_filter(pattern)" do
    test "does not transform filter" do
      filter = quote do: fn %A{key1: 3} -> true end
      assert Compiler.to_filter(filter) == filter
    end

    test "with no guard" do
      expected = quote do: fn %A{key1: 3} -> true end
      assert Compiler.to_filter(quote do: %A{key1: 3}) == expected
    end

    test "with guard" do
      expected = quote do: fn %A{key1: a} when is_list(a) -> true end
      assert Compiler.to_filter(quote do: %A{key1: a} when is_list(a)) == expected
    end
  end

  test "match with <> operator in expression" do
    pattern = Pattern.new(fn %A{key1: "ab" <> x} -> x == "aaa" or x == "bbb" end)

    expected =
      and_(
        and_(
          and_(op_(:is_map, [access_([])]), op_(:==, [access_([:__struct__]), A])),
          and_(
            op_(:is_binary, [access_([:key1])]),
            call_(String, :starts_with?, [access_([:key1]), "ab"])
          )
        ),
        or_(
          op_(:==, [call_(String, :trim_leading, [access_([:key1]), "ab"]), "aaa"]),
          op_(:==, [call_(String, :trim_leading, [access_([:key1]), "ab"]), "bbb"])
        )
      )

    assert expected == pattern.code
  end

  defp call(_), do: true
end
