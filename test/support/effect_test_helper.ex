defmodule Cizen.EffectTestHelper do
  @moduledoc false

  defmodule TestEvent do
    @moduledoc false
    defstruct [:value]
  end

  defmodule TestEffect do
    @moduledoc false
    defstruct value: nil, resolve_immediately: false, alias_of: nil, ignores: []

    alias Cizen.Effect
    use Effect

    @impl true
    def init(_handler, effect) do
      if is_nil(effect.alias_of) do
        if effect.resolve_immediately do
          {:resolve, effect.value}
        else
          effect.value
        end
      else
        {:alias_of, effect.alias_of}
      end
    end

    @impl true
    def handle_event(_handler, event, effect, _value) do
      %__MODULE__{value: value, ignores: ignores} = effect

      if event.value == :ignored or event.value in ignores do
        value
      else
        if value == event.value do
          {:resolve, value}
        else
          {:consume, value}
        end
      end
    end
  end
end
