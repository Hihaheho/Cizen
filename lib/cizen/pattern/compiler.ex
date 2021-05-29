defmodule Cizen.Pattern.Compiler do
  @moduledoc false
  alias Cizen.Pattern.Code
  import Code, only: [as_code: 2]

  # filter style
  # input: `fn %{a: a} -> a == :ok end`
  def compile(pattern_or_filter, env) do
    {:fn, _, fncases} = to_filter(pattern_or_filter)
    # Merges cases
    {codes, _guards} =
      fncases
      |> Enum.reduce({[], []}, fn fncase, {codes, guards_of_above_fncases} ->
        {code, guard} = read_fncase(fncase, env)

        code =
          guards_of_above_fncases
          |> Enum.reverse()
          # Makes guards of above fncases nagative
          |> Enum.map(fn guard -> Code.not_(guard) end)
          # guard for this case
          |> List.insert_at(-1, guard)
          |> Code.all()
          |> gen_and(code)

        {[code | codes], [guard | guards_of_above_fncases]}
      end)

    codes
    |> Enum.reverse()
    |> Code.any()
  end

  # input `fn case1; case2 end`
  def to_filter({:fn, _, _fncases} = filter), do: filter
  def to_filter(pattern), do: quote(do: fn unquote(pattern) -> true end)

  # Reads fncase
  @spec read_fncase(Code.ast(), Macro.Env.t()) :: {Code.t(), [Code.t()]}
  defp read_fncase({:->, _, [[header], {:__block__, _, [expression]}]}, env) do
    # Ignores :__block__
    read_fncase({:->, [], [[header], expression]}, env)
  end

  # input: header -> expression
  defp read_fncase({:->, _, [[header], expression]}, env) do
    {vars, guard_codes} = read_header(header, env)

    guard =
      guard_codes
      |> Enum.reverse()
      |> Code.all()

    code =
      expression
      |> Code.expand_embedded_patterns(env)
      |> Code.translate(vars, env)

    {code, guard}
  end

  # Reads prefix and guard codes (reversed) from the given expression
  @spec read_header(Code.ast(), Macro.Env.t()) :: {Code.vars(), [Code.t()]}
  defp read_header(header, env), do: read_header(header, %{}, [], [], env)

  # * vars - accessible variables
  # * codes - codes generated from guard expressions (reversed order of execution)
  # * prefix - prefix keys
  # * env - `Macro.Env`
  @spec read_header(Code.ast(), Code.vars(), [Code.t()], [term], Macro.Env.t()) ::
          {Code.vars(), [Code.t()]}
  # input: `%{key: atom} when atom in [:a, :b, :c]`
  defp read_header({:when, _, [header, guard]}, vars, assertion_codes, prefix, env) do
    # read the header
    {vars, assertion_codes} = read_header(header, vars, assertion_codes, prefix, env)
    # translate the guard case
    assertion_codes = [Code.translate(guard, vars, env) | assertion_codes]
    {vars, assertion_codes}
  end

  # input: `%MyStruct{key1: var, key2: 42}`
  defp read_header({:%, _, [module, {:%{}, _, pairs}]}, vars, assertion_codes, prefix, env) do
    context_value = Code.access_(prefix)

    assertion_code =
      as_code value: context_value do
        is_map(value) and value.__struct__ == module
      end

    handle_key_value_pairs(pairs, vars, [assertion_code | assertion_codes], prefix, env)
  end

  # input: `%{key1: var, key2: 42}`
  defp read_header({:%{}, _, pairs}, vars, assertion_codes, prefix, env) do
    context_value = Code.access_(prefix)

    assertion_code =
      as_code value: context_value do
        is_map(value)
      end

    assertion_code_checks_keys_exists =
      pairs
      |> Enum.map(fn {key, _value} ->
        as_code value: context_value do
          Map.has_key?(value, key)
        end
      end)

    assertion_codes = assertion_code_checks_keys_exists ++ [assertion_code | assertion_codes]

    handle_key_value_pairs(pairs, vars, assertion_codes, prefix, env)
  end

  # input: `%MyStruct{a: 1} = var`
  defp read_header({:=, _, [struct, {var, meta, context}]}, vars, assertion_codes, prefix, env) do
    # read the struct
    {vars, assertion_codes} = read_header(struct, vars, assertion_codes, prefix, env)
    # read the var
    read_header({var, meta, context}, vars, assertion_codes, prefix, env)
  end

  # input: `^var`
  defp read_header({:^, _, [var]}, vars, assertion_codes, prefix, _env) do
    context_value = Code.access_(prefix)

    assertion_code =
      as_code value: context_value do
        value == var
      end

    {vars, [assertion_code | assertion_codes]}
  end

  # input: `"str" <> var`
  defp read_header({:<>, _, [leading, {var_name, _, _}]}, vars, assertion_codes, prefix, _env) do
    context_value = Code.access_(prefix)

    assertion_code =
      as_code value: context_value do
        is_binary(value) and String.starts_with?(value, leading)
      end

    assertion_codes = [assertion_code | assertion_codes]

    var_code =
      as_code value: context_value do
        String.trim_leading(value, leading)
      end

    vars = Map.put(vars, var_name, var_code)

    {vars, assertion_codes}
  end

  # input: `var`
  defp read_header({var_name, _, _}, vars, assertion_codes, prefix, _env) do
    case Map.get(vars, var_name) do
      # bind the current value to the new variable.
      nil ->
        vars = Map.put(vars, var_name, Code.access_(prefix))
        {vars, assertion_codes}

      # variable exists.
      var_code ->
        context_value = Code.access_(prefix)

        assertion_code =
          as_code value: context_value, var: var_code do
            value == var
          end

        {vars, [assertion_code | assertion_codes]}
    end
  end

  # input: `42`
  defp read_header(actual_value, vars, assertion_codes, prefix, _env) do
    context_value = Code.access_(prefix)

    assertion_code =
      as_code value: context_value do
        value == actual_value
      end

    {vars, [assertion_code | assertion_codes]}
  end

  # Handles `[key1: var, key2: 42]` for a map or struct
  defp handle_key_value_pairs(pairs, vars, codes, prefix, env) do
    pairs
    |> Enum.reduce({vars, codes}, fn {key, value}, {vars, codes} ->
      read_header(value, vars, codes, List.insert_at(prefix, -1, key), env)
    end)
  end

  defp gen_and(true, arg2), do: arg2
  defp gen_and(arg1, true), do: arg1
  defp gen_and(arg1, arg2), do: Code.and_(arg1, arg2)
end
