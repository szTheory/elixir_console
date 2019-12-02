defmodule ElixirConsole.Sandbox.AllowedElixirModules do
  @moduledoc """
  Analyze the AST to filter out non white-listed modules and kernel functions
  """

  alias ElixirConsole.Sandbox.CommandValidator
  @behaviour CommandValidator

  @valid_modules ~w(
    Kernel
    Atom
    Base
    Bitwise
    Date
    DateTime
    Float
    Integer
    NaiveDateTime
    Regex
    String
    Time
    Tuple
    URI
    Version
    Version.Requirement
    Access
    Date.Range
    Enum
    Keyword
    List
    Map
    MapSet
    Range
    Stream
    OptionParser
    Path
    Collectable
    Enumerable
  )a

  @impl CommandValidator
  def validate(ast) do
    {_ast, result} = Macro.prewalk(ast, [], &valid?(&1, &2))

    result
    |> Enum.filter(&match?({:error, _}, &1))
    |> Enum.map(fn {:error, module} -> module end)
    |> Enum.dedup()
    |> case do
      [] ->
        :ok

      invalid_modules ->
        {:error,
         "It is not allowed to use some Elixir modules. " <>
           "Not allowed modules attempted: #{inspect(invalid_modules)}"}
    end
  end

  defp valid?({:__aliases__, _, [module]} = elem, acc) when module not in @valid_modules do
    {elem, [{:error, module} | acc]}
  end

  defp valid?(elem, acc), do: {elem, [:ok | acc]}
end