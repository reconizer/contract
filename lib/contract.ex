defmodule Contract do
  @type validate_params_t :: %{required(atom()) => any()}
  @type error :: {:error, any()}
  @type validate_params :: validate_params_t | {:ok, validate_params_t} | error
  @type validate_result :: {:ok, %{required(atom()) => any()}} | error

  def plug({:ok, params}, plugs), do: plug(params, plugs)
  def plug({:error, _} = error, _), do: error

  def plug(params, plugs) do
    plugs
    |> Enum.reduce({:ok, params}, fn
      {plug_key, plug_fun}, {:ok, params} when is_function(plug_fun, 1) ->
        params
        |> Map.get(plug_key, :undefined)
        |> case do
          value ->
            plug_fun.(value)
            |> case do
              {:ok, value} -> {:ok, params |> Map.put(plug_key, value)}
              other -> other
            end
        end

      {plug_key, plug_fun}, {:ok, params} when is_function(plug_fun, 2) ->
        params
        |> Map.get(plug_key, :undefined)
        |> case do
          value ->
            plug_fun.(value, params)
            |> case do
              {:ok, value} -> {:ok, params |> Map.put(plug_key, value)}
              other -> other
            end
        end

      {_plug_key, _plug_fun}, {:error, _} = error ->
        error
    end)
  end

  def default({:ok, params}, defaults) do
    default(params, defaults)
  end

  def default({:error, _} = error, _) do
    error
  end

  def default(params, defaults) do
    defaults
    |> Enum.reduce(params, fn {key, value}, params ->
      params
      |> Map.get(key)
      |> case do
        nil -> params |> Map.put(key, value)
        _ -> params
      end
    end)
  end

  def cast({:ok, params}, types) do
    cast(params, types)
  end

  def cast({:error, _} = error, _) do
    error
  end

  def cast(params, types) do
    type_keys = types |> Map.keys() |> Enum.map(&"#{&1}")

    initial =
      params
      |> Enum.map(fn
        {key, _value} when is_atom(key) ->
          {key, nil}

        {key, _value} when is_bitstring(key) ->
          key
          |> string_to_atom
          |> case do
            nil -> nil
            key -> {key, nil}
          end
      end)
      |> Enum.filter(fn
        nil ->
          nil

        {key, _value} = param ->
          ("#{key}" in type_keys)
          |> case do
            true -> param
            _ -> nil
          end
      end)
      |> Enum.into(%{})

    {initial, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> resolve_changeset
  end

  @spec validate(validate_params, Map.t()) :: validate_result
  def validate({:ok, params}, validations), do: validate(params, validations)
  def validate({:error, _} = error, _), do: error

  def validate(params, validations) do
    param_keys = for key <- params |> Map.keys(), do: {key, :any}, into: %{}
    validation_keys = for key <- validations |> Map.keys(), do: {key, :any}, into: %{}

    keys = Map.merge(param_keys, validation_keys)

    initial =
      params
      |> Enum.map(fn
        {key, _value} -> {key, nil}
      end)
      |> Enum.into(%{})

    changeset =
      {initial, keys}
      |> Ecto.Changeset.cast(params, keys |> Map.keys())

    validations
    |> Enum.reduce(changeset, &validate_changeset/2)
    |> resolve_changeset
  end

  defp resolve_changeset(changeset) do
    changeset
    |> case do
      %{valid?: true} = changeset ->
        {:ok, changeset |> Ecto.Changeset.apply_changes()}

      errors ->
        {:error, errors |> resolve}
    end
  end

  defp resolve(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn
        {key, {:array, min..max}}, acc ->
          String.replace(acc, "%{#{key}}", "#{to_string([min, max] |> Enum.join(" "))}[]")

        {key, min..max}, acc ->
          String.replace(acc, "%{#{key}}", to_string([min, max] |> Enum.join(" ")))

        {key, {:array, value}}, acc ->
          String.replace(acc, "%{#{key}}", "#{to_string(value)}[]")

        {key, value}, acc ->
          String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

  defp validate_changeset({key, key_validations}, changeset) when is_list(key_validations) do
    key_validations
    |> Enum.reduce(changeset, fn validation, changeset ->
      changeset
      |> do_validate(key, validation)
    end)
  end

  defp validate_changeset({key, key_validation}, changeset) do
    changeset
    |> do_validate(key, key_validation)
  end

  defp do_validate(changeset, key, :required) do
    changeset
    |> Ecto.Changeset.validate_required(key)
  end

  defp do_validate(changeset, key, :confirmation) do
    changeset
    |> Ecto.Changeset.validate_confirmation(key, required: true)
  end

  defp do_validate(changeset, key, {:min_length, value}) do
    changeset
    |> Ecto.Changeset.validate_length(key, min: value)
  end

  defp do_validate(changeset, key, {:max_length, value}) do
    changeset
    |> Ecto.Changeset.validate_length(key, max: value)
  end

  defp do_validate(changeset, key, {:equal_length, value}) do
    changeset
    |> Ecto.Changeset.validate_length(key, is: value)
  end

  defp do_validate(changeset, key, {:inclusion, list}) do
    changeset
    |> Ecto.Changeset.validate_inclusion(key, list)
  end

  defp do_validate(changeset, key, {:format, format}) do
    changeset
    |> Ecto.Changeset.validate_format(key, format)
  end

  defp do_validate(changeset, key, fun) when is_function(fun, 1) do
    changeset
    |> Ecto.Changeset.validate_change(key, fn _, value ->
      fun.(value)
      |> case do
        true -> []
        false -> [{key, "is invalid"}]
        nil -> []
        error -> [{key, error}]
      end
    end)
  end

  defp do_validate(changeset, key, fun) when is_function(fun, 2) do
    changeset
    |> Ecto.Changeset.validate_change(key, fn _, value ->
      fun.(value, Ecto.Changeset.apply_changes(changeset))
      |> case do
        true -> []
        false -> [{key, "is invalid"}]
        nil -> []
        error -> [{key, error}]
      end
    end)
  end

  defp do_validate(changeset, _, _) do
    changeset
  end

  defp string_to_atom(value) do
    value
    |> String.to_existing_atom()
  rescue
    _ -> nil
  end
end
