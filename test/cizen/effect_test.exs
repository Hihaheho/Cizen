defmodule Cizen.EffectTest do
  use ExUnit.Case
  alias Cizen.EffectTestHelper.TestEvent

  alias Cizen.Effect
  alias Cizen.SagaID

  defmodule TestEffect do
    defstruct [:init_value, :handle_event_value, :alias_of]

    alias Cizen.Effect
    use Effect

    @impl true
    def init(_handler, effect) do
      if is_nil(effect.alias_of) do
        effect.init_value
      else
        {:alias_of, effect.alias_of}
      end
    end

    @impl true
    def handle_event(_handler, _event, effect, _state) do
      effect.handle_event_value
    end
  end

  describe "Effect.init/2" do
    test "resolves" do
      id = SagaID.new()
      effect = %TestEffect{init_value: {:resolve, :a}}
      assert {:resolve, :a} = Effect.init(id, effect)
    end

    test "recursively use aliases" do
      id = SagaID.new()
      final_effect = %TestEffect{init_value: :a}

      effect = %TestEffect{
        alias_of: %TestEffect{
          alias_of: final_effect
        }
      }

      assert {^final_effect, :a} = Effect.init(id, effect)
    end
  end

  describe "Effect.handle_event/2" do
    test "returns the same result as the given effect" do
      id = SagaID.new()
      effect = %TestEffect{handle_event_value: :a}
      event = %TestEvent{}
      assert :a = Effect.handle_event(id, event, effect, :ok)
    end
  end

  describe "use Cizen.Effect" do
    defmodule Repeat do
      use Cizen.Effect
      use Cizen.Effects, only: [Chain]
      defstruct [:count, :effect, :pid]
      @impl true
      def expand(id, %__MODULE__{count: count, effect: effect, pid: pid}) do
        effects =
          [effect]
          |> Stream.cycle()
          |> Enum.take(count)

        send(pid, id)

        %Chain{
          effects: effects
        }
      end
    end

    test "defines custom effect" do
      use Cizen.Effects, only: [Chain, Receive]
      id = SagaID.new()
      expected = Effect.init(id, %Chain{effects: [%Receive{}, %Receive{}, %Receive{}]})
      assert expected == Effect.init(id, %Repeat{count: 3, effect: %Receive{}, pid: self()})
      assert_receive ^id
    end
  end
end
