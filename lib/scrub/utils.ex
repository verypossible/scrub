defmodule Scrub.Utils do
  @doc """
  Convert an IP address to tuple form
  Examples:
      iex> VintageNet.IP.ip_to_tuple("192.168.0.1")
      {:ok, {192, 168, 0, 1}}
      iex> VintageNet.IP.ip_to_tuple({192, 168, 1, 1})
      {:ok, {192, 168, 1, 1}}
      iex> VintageNet.IP.ip_to_tuple("fe80::1")
      {:ok, {65152, 0, 0, 0, 0, 0, 0, 1}}
      iex> VintageNet.IP.ip_to_tuple({65152, 0, 0, 0, 0, 0, 0, 1})
      {:ok, {65152, 0, 0, 0, 0, 0, 0, 1}}
      iex> VintageNet.IP.ip_to_tuple("bologna")
      {:error, "Invalid IP address: bologna"}
  """
  @spec ip_to_tuple(VintageNet.any_ip_address()) ::
          {:ok, :inet.ip_address()} | {:error, String.t()}
  def ip_to_tuple({a, b, c, d} = ipa)
      when a >= 0 and a <= 255 and b >= 0 and b <= 255 and c >= 0 and c <= 255 and d >= 0 and
             d <= 255,
      do: {:ok, ipa}

  def ip_to_tuple({a, b, c, d, e, f, g, h} = ipa)
      when a >= 0 and a <= 65535 and b >= 0 and b <= 65535 and c >= 0 and c <= 65535 and d >= 0 and
             d <= 65535 and
             e >= 0 and e <= 65535 and f >= 0 and f <= 65535 and g >= 0 and g <= 65535 and h >= 0 and
             h <= 65535,
      do: {:ok, ipa}

  def ip_to_tuple(ipa) when is_binary(ipa) do
    case :inet.parse_address(to_charlist(ipa)) do
      {:ok, addr} -> {:ok, addr}
      {:error, :einval} -> {:error, "Invalid IP address: #{ipa}"}
    end
  end

  def ip_to_tuple(ipa), do: {:error, "Invalid IP address: #{inspect(ipa)}"}

  @doc """
  Raising version of ip_to_tuple/1
  """
  @spec ip_to_tuple!(VintageNet.any_ip_address()) :: :inet.ip_address()
  def ip_to_tuple!(ipa) do
    case ip_to_tuple(ipa) do
      {:ok, addr} ->
        addr

      {:error, error} ->
        raise ArgumentError, error
    end
  end
end
