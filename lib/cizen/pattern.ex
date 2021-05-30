defmodule Cizen.Pattern do
  @moduledoc """
  Creates a pattern.

  ## Basic

      Pattern.new(
        fn %Event{body: %SomeEvent{field: value}} ->
          value == :a
        end
      )

      Pattern.new(
        fn %Event{body: %SomeEvent{field: :a}} -> true end
      )
      # or shortly:
      Pattern.new(%SomeEvent{field: :a})

      value = :a
      Pattern.new(%SomeEvent{field: ^value})

  ## With guard

      Pattern.new(
        fn %Event{source_saga_id: source} when not is_nil(source) -> true end
      )

  ## Matches all

      Pattern.new(_)

  ## Matches the specific type of struct

      Pattern.new(%SomeEvent{})

  ## Compose patterns

      Pattern.new(
        fn %SomeEvent{field: value} ->
          Pattern.match?(other_pattern, value)
        end
      )

  ## Multiple patterns

      Pattern.any([
        Pattern.new(fn %Resolve{id: id} -> id == "some id" end),
        Pattern.new(fn %Reject{id: id} -> id == "some id" end)
      ])

  ## Multiple cases

      Pattern.new(fn
        %SomeEvent{field: :ignore} -> false
        %SomeEvent{field: value} -> true
      end)
  """

  @type t :: %__MODULE__{}

  defstruct code: true

  alias Cizen.Pattern.{Code, Compiler}

  @doc """
  Creates a pattern with the given anonymous function or pattern match.
  """
  defmacro new(pattern) do
    function =
      pattern
      |> Compiler.to_filter()

    code = Compiler.compile(pattern, __CALLER__)

    quote do
      # Delegates code checking to the compiler.
      _ = unquote(function)

      %unquote(__MODULE__){
        code: unquote(code)
      }
    end
  end

  @doc """
  Checks whether the given struct matches or not.
  """
  @spec match?(t, term) :: boolean
  def match?(%__MODULE__{code: code}, struct) do
    if eval(code, struct), do: true, else: false
  end

  @doc """
  Joins the given patterns with `and`.
  """
  @spec all([t()]) :: t()
  def all(patterns) do
    code = patterns |> Enum.map(& &1.code) |> Code.all()
    %__MODULE__{code: code}
  end

  @doc """
  Joins the given patterns with `or`.
  """
  @spec any([t()]) :: t()
  def any(patterns) do
    code = patterns |> Enum.map(& &1.code) |> Code.any()
    %__MODULE__{code: code}
  end

  def eval({:access, keys}, struct) do
    Enum.reduce(keys, struct, fn key, struct ->
      Map.get(struct, key)
    end)
  end

  def eval({:call, [{module, fun} | args]}, struct) do
    args = args |> Enum.map(&eval(&1, struct))
    apply(module, fun, args)
  end

  @macro_unary_operators [:is_nil, :to_string, :to_charlist, :not, :!]
  for operator <- @macro_unary_operators do
    def eval({unquote(operator), [arg]}, struct) do
      Kernel.unquote(operator)(eval(arg, struct))
    end
  end

  @macro_binary_operators [:and, :&&, :or, :||, :in, :.., :<>]
  for operator <- @macro_binary_operators do
    def eval({unquote(operator), [arg1, arg2]}, struct) do
      Kernel.unquote(operator)(eval(arg1, struct), eval(arg2, struct))
    end
  end

  def eval({operator, args}, struct) do
    args = args |> Enum.map(&eval(&1, struct))
    apply(Kernel, operator, args)
  end

  def eval(value, _struct) do
    value
  end
end
