# Test

You can test Cizen applications with using `Cizen.Test`.

## Saga Cleanup

With `use Cizen.Test`, all sagas started in a test are automatically cleaned up after the test exits.

### Example

    defmodule SomeTest do
      use ExUnit.Case
      use Cizen.Test

      test "start SomeSaga" do
        handle fn ->
          # This saga will end after the test exits.
          perform %Start{
            saga: %SomeSaga{}
          }
        end
      end
    end

## Timeout

You can use `Cizen.Test.assert_handle/1` and `Cizen.Test.assert_perform/1` to assert that the given block/effect is finished/performed in the given timeout.

### Example

    defmodule SomeTest do
      use ExUnit.Case
      use Cizen.Test

      test "some test" do
        assert_handle fn ->
          assert_perform %Start{
            saga: %SomeSaga{}
          }
        end
      end

      test "custom timeout" do
        assert_handle 100, fn ->
          assert_perform 10, %Start{
            saga: %SomeSaga{}
          }
        end
      end
    end
