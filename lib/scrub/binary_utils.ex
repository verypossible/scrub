defmodule Scrub.BinaryUtils do
  @moduledoc false

  defmacro sint do
    quote do: little - signed - 8
  end

  defmacro int do
    quote do: little - signed - 16
  end

  defmacro dint do
    quote do: little - signed - 32
  end

  defmacro lint do
    quote do: little - signed - 64
  end

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

  defmacro real do
    quote do: little - signed - float - 32
  end

  defmacro lreal do
    quote do: little - signed - float - 64
  end
end
