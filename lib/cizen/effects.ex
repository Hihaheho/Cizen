defmodule Cizen.Effects do
  @moduledoc """
  A convenience module to use effects.

  `use Cizen.Effects` aliases all effects.
  It alse aliases Map effect, but `Elixir.Map`'s APIs are still available.

  ## Alias all effects

      use Cizen.Effects

  ## Alias only specified effects

      use Cizen.Effects, only: [Subscribe, Receive, Dispatch]
  """

  @effects [
    All,
    Chain,
    Dispatch,
    End,
    Fork,
    Map,
    Monitor,
    Race,
    Receive,
    Start,
    Subscribe
  ]

  defmacro __using__(opts) do
    effects = Keyword.get(opts, :only, @effects)

    for effect <- effects do
      case effect do
        Map ->
          quote do
            alias Cizen.Effects.HybridMap, as: Map
          end

        effect ->
          quote do
            alias Cizen.Effects.unquote(effect)
          end
      end
    end
  end

  defmodule HybridMap do
    @moduledoc """
    Hybrid module of `Elixir.Map` and `Cizen.Effects.Map`

    This module is used with `Cizen.Effects.__using__/1` in order to avoid
    conflict between `Elixir.Map` and `Cizen.Effects.Map`
    """
    defstruct [:effect, :transform]
    use Cizen.Effect

    alias Cizen.Effects.Map

    @impl true
    def init(_id, %__MODULE__{effect: effect, transform: transform}) do
      {:alias_of, %Map{effect: effect, transform: transform}}
    end

    @impl true
    def handle_event(_, _, _, _), do: :ok

    @deprecated_functions [{:replace, 3}, {:size, 1}]
    for {name, arity} <- Elixir.Map.__info__(:functions) do
      unless {name, arity} in @deprecated_functions do
        args =
          [:ok]
          |> Stream.cycle()
          |> Stream.transform(0, fn _, acc ->
            {[{String.to_atom(<<?a + acc>>), [], nil}], acc + 1}
          end)
          |> Enum.take(arity)

        defdelegate unquote({name, [], args}), to: Elixir.Map
      end
    end
  end
end
