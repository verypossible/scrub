defmodule Scrub.CIP.Type do
  import Scrub.BinaryUtils, warn: false

  def decode(<<0x00::uint>>) do
    nil
  end

  def decode(<<0xC1, 0x00::uint>>), do: false
  def decode(<<0xC1, 0x01::uint>>), do: true

  def decode(<<0xCA, 0x00, value::real>>) do
    value
  end

  def decode(<<_, value::binary>>) do
    {:unknown, value}
  end
end
