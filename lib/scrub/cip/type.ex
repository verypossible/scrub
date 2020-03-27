defmodule Scrub.CIP.Type do
  import Scrub.BinaryUtils, warn: false

  alias Scrub.CIP.Symbol

  def decode(<<0xA0, 0x02, _crc :: uint, data :: binary>>, %{members: members} = structure) do
    IO.puts "Template: #{structure.template_name}"
    Enum.reduce(members, [], fn
      %{name: <<"ZZZZZZZZZ", _tail :: binary>>}, acc -> acc
      %{type: :bool, offset: offset, bit_location: location} = member, acc ->
        <<_offset :: binary(offset, 8), host :: binary(1, 8), _tail :: binary>> = data
        offset = 7 - location
        <<_offset :: binary(offset, 1), value :: binary(1, 1), _pad :: binary(location, 1)>> = host
        {value, _} = decode_type(:bool, value)
        [Map.put(member, :value, value) | acc]

      %{type: type, offset: offset, array_length: 0} = member, acc ->
        <<_offset :: binary(offset, 8), tail :: binary()>> = data
        {value, _tail} = decode_type(type, tail)
        [Map.put(member, :value, value) | acc]

      %{type: type, offset: offset, array_length: length} = member, acc ->
        <<_offset :: binary(offset, 8), data :: binary()>> = data
          {values, _} =
            Enum.reduce(1..length, {[], data}, fn(_, {values, data}) ->
              {value, data} = decode_type(type, data)
              {[value | values], data}
            end)
        [Map.put(member, :value, values) | acc]
    end)
    |> Enum.reverse()
  end

  def decode(<<type :: binary(2, 8), data :: binary()>>, _t) do
    type = Symbol.type_decode(type)
    case decode_type(type, data) do
      {data, <<>>} -> data
      more_data -> more_data
    end
  end

  def decode_type(:bool, <<0x01, tail :: binary>>), do: {true, tail}
  def decode_type(:bool, <<0x00, tail :: binary>>), do: {false, tail}
  def decode_type(:bool, <<1 :: size(1), tail :: binary>>), do: {true, tail}
  def decode_type(:bool, <<0 :: size(1), tail :: binary>>), do: {false, tail}
  def decode_type(:real, <<0x00, value::real, tail :: binary>>), do: {value, tail}
  def decode_type(:dword, <<value :: binary(4, 8), tail :: binary()>>), do: {value, tail}
  def decode_type(_, <<0x00::uint, tail :: binary>>), do: {nil, tail}
  def decode_type(type, data), do: {data, <<>>}
end
