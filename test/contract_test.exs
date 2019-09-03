defmodule ContractTest do
  use ExUnit.Case
  doctest Contract

  test "cast/2" do
    params = %{"foo" => "bar", "bar" => 2, "test" => [1, 2, 3, 4]}

    assert {:ok, _} =
             params |> Contract.cast(%{foo: :string, bar: :integer, test: {:array, :integer}})

    assert {:error, _} = params |> Contract.cast(%{bar: :string})
  end

  test "cast/2 removes unknown parameters" do
    params = %{"foo" => "Bar", "bar" => "baz", "test" => 1}

    assert {:ok, casted_params} = params |> Contract.cast(%{foo: :string})

    assert casted_params == %{foo: "Bar"}

    params = %{foo: "Bar", bar: "baz", test: 1}
    assert {:ok, casted_params} = params |> Contract.cast(%{foo: :string})

    assert casted_params == %{foo: "Bar"}
  end

  test "cast/2 with unknown atom string" do
    params = %{"some_non_existent_atom" => "bar", "bar" => 2, "test" => [1, 2, 3, 4]}

    assert {:ok, %{bar: _, test: _}} =
             params |> Contract.cast(%{foo: :string, bar: :integer, test: {:array, :integer}})

    assert {:error, _} = params |> Contract.cast(%{bar: :string})
  end

  test "cast/2 with atoms" do
    params = %{foo: "bar", test: [1, 2, 3]}

    assert {:ok, %{foo: _, test: _}} =
             params |> Contract.cast(%{foo: :string, test: {:array, :integer}})

    assert {:error, _} = params |> Contract.cast(%{test: :string})
  end

  test "cast/2 with some fields null" do
    params = %{"foo" => "bar", "test" => "", "bar" => nil}

    assert {:ok, %{foo: _, test: _, bar: _}} =
    params |> Contract.cast(%{foo: :string, test: :string, bar: :integer})
  end

  test "plug/2" do
    params = %{some: "parameter", other: 123, test: [1, 2, 3, 4]}

    result =
      params
      |> Contract.plug(
        some: fn value ->
          {:ok, "#{value} - test"}
        end,
        other: fn value ->
          {:ok, value + 1111}
        end,
        test: fn value ->
          {:ok, value ++ [5, 6, 7, 8]}
        end
      )

    assert {:ok, %{some: "parameter - test", other: 1234, test: [1, 2, 3, 4, 5, 6, 7, 8]}} ==
             result
  end

  test "plug/2 accepting 2 arguments for function" do
    params = %{some: "parameter", other: 123}

    result =
      params
      |> Contract.plug(
        some: fn value, params ->
          {:ok, "#{value} - #{params.other}"}
        end
      )

    assert {:ok, %{some: "parameter - 123", other: 123}} == result
  end

  test "plug/2 with failed plug" do
    params = %{some: "parameter", other: 123, test: [1, 2, 3, 4]}

    result =
      params
      |> Contract.plug(
        some: fn _value ->
          {:error, :is_invalid}
        end,
        other: fn value ->
          {:ok, value + 1111}
        end,
        test: fn _value ->
          {:ok, :is_also_invalid}
        end
      )

    assert {:error, :is_invalid} == result
  end

  test "plug/2 without parameter present" do
    params = %{}

    result =
      params
      |> Contract.plug(%{
        test: fn _ ->
          {:ok, "test"}
        end
      })

    assert {:ok, %{test: "test"}} == result
    params = %{test: "value"}

    result =
      params
      |> Contract.plug(%{
        test1: fn _, params ->
          {:ok, params.test}
        end
      })

    assert {:ok, %{test1: "value", test: "value"}} == result
  end

  test "validate/2 confirmation" do
    params = %{password: "testtest", password_confirmation: "testtest"}

    assert {:ok, _} = params |> Contract.validate(%{password: :confirmation})

    assert {:error, _} =
             %{params | password_confirmation: nil}
             |> Contract.validate(%{password: :confirmation})

    assert {:error, _} =
             %{password: "Test"}
             |> Contract.validate(%{password: :confirmation})
  end

  test "validate/2 with passing changeset" do
    validator = fn _password, changes ->
      changes
      |> Map.get(:password)
      |> case do
        nil ->
          true

        password ->
          password == Map.get(changes, :password_confirmation)
      end
    end

    params = %{}

    assert {:ok, _} =
             params
             |> Contract.validate(%{
               password: &validator.(&1, &2)
             })

    params = %{password: "testtest"}

    assert {:error, _} =
             params
             |> Contract.validate(%{
               password: &validator.(&1, &2)
             })

    params = %{password: "testtest", password_confirmation: "test"}

    assert {:error, _} =
             params
             |> Contract.validate(%{
               password: &validator.(&1, &2)
             })

    params = %{password: "testtest", password_confirmation: "testtest"}

    assert {:ok, _} =
             params
             |> Contract.validate(%{
               password: &validator.(&1, &2)
             })
  end

  test "validate/2 with atom keys" do
    params = %{foo: 2}

    assert {:ok, _} = params |> Contract.validate(%{foo: :required})
    assert {:error, _} = params |> Contract.validate(%{bar: :required})

    assert {:ok, _} =
             params
             |> Contract.validate(%{
               foo: fn value ->
                 (value == 2)
                 |> case do
                   true -> nil
                   _ -> "invalid value"
                 end
               end
             })

    assert {:error, _} =
             params
             |> Contract.validate(%{
               foo: fn value ->
                 (value > 2)
                 |> case do
                   true -> nil
                   _ -> "must be greater than 2"
                 end
               end
             })

    assert {:error, _} =
             params
             |> Contract.validate(%{
               foo: fn value ->
                 value > 2
               end
             })

    assert {:ok, _} =
             params
             |> Contract.validate(%{
               foo: fn value ->
                 value >= 2
               end
             })
  end
end
