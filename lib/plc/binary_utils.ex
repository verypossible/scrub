defmodule PLC.BinaryUtils do
  @moduledoc false

  defmacro int64 do
    quote do: little - signed - 64
  end

  defmacro int32 do
    quote do: little-signed - 32
  end

  defmacro int16 do
    quote do: little - signed - 16
  end

  defmacro uint16 do
    quote do: little - unsigned - 16
  end

  defmacro uint32 do
    quote do: little - unsigned - 32
  end

  defmacro uint64 do
    quote do: little - unsigned - 64
  end

  defmacro int8 do
    quote do: little - signed - 8
  end

  defmacro float64 do
    quote do: little - float - 64
  end

  defmacro float32 do
    quote do: little - float - 32
  end

  defmacro binary(size) do
    quote do: little - binary - size(unquote(size))
  end

  defmacro binary(size, unit) do
    quote do: little - binary - size(unquote(size)) - unit(unquote(unit))
  end
end
