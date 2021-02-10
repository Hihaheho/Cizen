defmodule Cizen.Automaton.PerformEffect do
  @moduledoc """
  An event to perform an effect.
  """

  @keys [:effect]
  @enforce_keys @keys
  defstruct @keys
end
