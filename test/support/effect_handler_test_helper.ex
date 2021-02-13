defmodule Cizen.EffectHandlerTestHelper do
  @moduledoc false

  defmodule TestEffectEvent do
    @moduledoc false
    defstruct [:value, :count, :extra]
  end

  defmodule TestEffect do
    @moduledoc false
    defstruct [:value, :resolve_immediately, :reset, :alias_of]

    alias Cizen.Effect

    use Effect

    @impl true
    def init(_handler, effect) do
      if is_nil(effect.alias_of) do
        count = 0

        if effect.resolve_immediately do
          {:resolve, {effect.value, count}}
        else
          count
        end
      else
        {:alias_of, effect.alias_of}
      end
    end

    @impl true
    def handle_event(_handler, %TestEffectEvent{} = body, effect, count) do
      if body.value == effect.value do
        count = count + 1

        if body.count <= count do
          {:resolve, {effect.value, count}}
        else
          {:consume, count}
        end
      else
        if effect.reset do
          0
        else
          count
        end
      end
    end

    def handle_event(_, _, _, count), do: count
  end
end
