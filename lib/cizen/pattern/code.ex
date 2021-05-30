defmodule Cizen.Pattern.Code do
  @moduledoc false
  alias Cizen.Pattern

  @type t :: {:access, keys} | {:call, [{module, fun} | [term]]} | {atom, [term]} | term
  @type ast :: any
  @type key :: term
  @type keys :: [key]
  @type vars :: %{atom => t}

  @doc false
  @spec translate(ast, vars, Macro.Env.t()) :: t
  def translate(expression, vars, env) do
    Macro.postwalk(expression, &walk(&1, vars, env))
  end

  defmacro as_code(vars, do: block) do
    # Puts :access_with_var label to each var to show an evaluated code of var includes :access code.
    vars = Enum.into(vars, %{}, fn {var_name, var} -> {var_name, {:access_with_var, [var]}} end)

    block
    |> translate(vars, __CALLER__)
    # Remove :access_with_var label
    |> Macro.postwalk(fn node ->
      case node do
        {:access_with_var, [var]} ->
          var

        node ->
          node
      end
    end)
  end

  @doc false
  @spec all([t]) :: t
  def all([]), do: true
  def all([code]), do: code
  def all([code | tail]), do: and_(code, all(tail))

  @doc false
  @spec any([t]) :: t
  def any([]), do: false
  def any([code]), do: code
  def any([code | tail]), do: or_(code, any(tail))

  @doc false
  @spec expand_embedded_patterns(ast, Macro.Env.t()) :: t
  def expand_embedded_patterns(expression, env) do
    Macro.prewalk(expression, fn node ->
      case node do
        {{:., _, [{:__aliases__, _, [:Pattern]}, :new]}, _, _} ->
          {pattern, _} =
            node
            |> Code.eval_quoted([], env)

          pattern

        node ->
          node
      end
    end)
  end

  @doc false
  # Puts prefix recursively to expand embedded patterns.
  def with_prefix({:access, keys}, prefix) do
    access_(prefix ++ keys)
  end

  def with_prefix({op, args}, prefix) when is_atom(op) and is_list(args) do
    args = Enum.map(args, &with_prefix(&1, prefix))
    op_(op, args)
  end

  def with_prefix(node, _prefix), do: node

  @additional_operators [:is_nil, :to_string, :to_charlist, :is_map, :is_binary]

  @spec walk(ast, vars, Macro.Env.t()) :: ast
  # input: `is_nil(x)`
  defp walk({op, _, args} = node, _vars, _env) when op in @additional_operators do
    gen_op(op, args, node)
  end

  # Skips . operator (field access is handled in below)
  defp walk({:., _, _} = node, _vars, _env), do: node

  # input: `value.key`
  defp walk({{:., _, [value, key]}, _, []}, _vars, _env) do
    gen_access_with_key(value, key)
  end

  # input: `value[key]`
  defp walk({{:., _, [Access, :get]}, _, [value, key]}, _vars, _env) do
    gen_access_with_key(value, key)
  end

  # input: `MyModule.func(arg1, arg2)`
  defp walk({{:., _, [module, function]}, _, args} = node, _vars, env) do
    expanded_module = Macro.expand(module, env)

    cond do
      expanded_module == Pattern and function == :match? ->
        # Embedded pattern
        case args do
          [%Pattern{code: code}, {:access, keys}] ->
            quote do
              unquote(__MODULE__).with_prefix(unquote(code), unquote(keys))
            end

          [pattern, {:access, keys}] ->
            quote do
              unquote(__MODULE__).with_prefix(unquote(pattern).code, unquote(keys))
            end
        end

      Enum.any?(args, &access_exists_?(&1)) ->
        call_(module, function, args)

      true ->
        node
    end
  end

  # input: `var`
  defp walk({var_name, _, third} = node, vars, _env)
       when is_atom(var_name) and not is_list(third) do
    if Map.has_key?(vars, var_name) do
      Map.get(vars, var_name)
    else
      node
    end
  end

  # input: `left and right` or `function_in_lexical_scope(arg1, arg2, ...)`
  defp walk({fun, _, args} = node, _vars, env) when is_atom(fun) do
    if Macro.operator?(fun, length(args)) do
      # input: `left and right`
      gen_op(fun, args, node)
    else
      # input: `function_in_lexical_scope(arg1, arg2, ...)`
      gen_call(node, env)
    end
  end

  defp walk(node, _vars, _env), do: node

  # Finds :access code in the given ast.
  defp access_exists_?(ast) do
    {_node, access_exists_?} =
      Macro.prewalk(ast, false, fn node, access_exists_? ->
        case node do
          {:access, _} ->
            {node, true}

          # See `as_code/2`
          {:access_with_var, [_var]} ->
            {node, true}

          node ->
            {node, access_exists_?}
        end
      end)

    access_exists_?
  end

  # Generates :op code if the args has any :access codes
  defp gen_op(fun, args, node) do
    if Enum.any?(args, &access_exists_?(&1)) do
      op_(fun, args)
    else
      node
    end
  end

  # Generates :call code if the args has any :access codes
  defp gen_call({fun, _, args} = node, env) do
    if Enum.any?(args, &access_exists_?(&1)) do
      arity = length(args)

      # find a function whitch matches the given name and arity.
      {module, _} =
        env.functions
        |> Enum.find({env.module, []}, fn {_module, functions} ->
          Enum.find(functions, fn
            {^fun, ^arity} ->
              true

            _ ->
              false
          end)
        end)

      call_(module, fun, args)
    else
      node
    end
  end

  # Appends key
  @spec append_key(keys | ast, key) :: t
  defp append_key(keys, key) when is_list(keys), do: List.insert_at(keys, -1, key)

  # this case is required because as_code/2 translates ast with keys generated on runtime.
  defp append_key(keys, key) do
    quote bind_quoted: [keys: keys, key: key] do
      List.insert_at(keys, -1, key)
    end
  end

  defp gen_access_with_key({:access, keys}, key) do
    access_(append_key(keys, key))
  end

  defp gen_access_with_key(var, key) do
    quote bind_quoted: [var: var, key: key] do
      alias Pattern.Code
      Code.__access_get__(var, key)
    end
  end

  def __access_get__(var, key) do
    case var do
      {:access, keys} ->
        access_(List.insert_at(keys, -1, key))

      var ->
        var[key]
    end
  end

  @spec and_(t, t) :: t
  def and_(left, right), do: {:and, [left, right]}
  @spec or_(t, t) :: t
  def or_(left, right), do: {:or, [left, right]}
  @spec access_(keys) :: t
  def access_(keys), do: {:access, keys}
  @spec op_(t, [t]) :: t
  def op_(op, args), do: {op, args}
  @spec call_(module, atom, [term]) :: t
  def call_(module, function, args), do: {:call, [{module, function} | args]}
  @spec not_(t) :: t
  def not_(code), do: op_(:not, [code])
end
