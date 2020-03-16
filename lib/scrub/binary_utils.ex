defmodule Scrub.BinaryUtils do
  @moduledoc false

  defmacro usint do
    quote do: little - unsigned - 8
  end

  defmacro uint do
    quote do: little - unsigned - 16
  end

  defmacro udint do
    quote do: little - unsigned - 32
  end

  defmacro ulint do
    quote do: little - unsigned - 64
  end

  defmacro octect do
    quote do: binary - 8
  end

  defmacro binary(size) do
    quote do: binary - size(unquote(size))
  end

  defmacro binary(size, unit) do
    quote do: binary - size(unquote(size)) - unit(unquote(unit))
  end

  # CIP Types

  defmacro real do
    quote do: little - signed - 32
  end
end
