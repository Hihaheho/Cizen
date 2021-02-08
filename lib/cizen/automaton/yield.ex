defmodule Cizen.Automaton.Yield do
  @moduledoc """
  An event fired when an automaton yields new state.
  """

  @keys [:saga_id, :state]
  @enforce_keys @keys
  defstruct @keys
end
