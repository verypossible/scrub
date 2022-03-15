defmodule Scrub.CIP.Type do
  import Scrub.BinaryUtils

  alias Scrub.CIP.Symbol

  def decode(<<0xA0, 0x02, _crc::uint, data::binary>>, %{members: members}) do
    Enum.reduce(members, [], fn
      %{name: <<"ZZZZZZZZZ", _tail::binary>>}, acc ->
        acc

      %{type: :bool, offset: offset, bit_location: location} = member, acc ->
        <<_offset::binary(offset, 8), host::binary(1, 8), _tail::binary>> = data
        offset = 7 - location
        <<_offset::binary(offset, 1), value::binary(1, 1), _pad::binary(location, 1)>> = host
        {value, _} = decode_type_data(:bool, value)
        [Map.put(member, :value, value) | acc]

      %{type: type, offset: offset, array_length: 0} = member, acc ->
        try do
          <<_offset::binary(offset, 8), tail::binary()>> = data
          {value, _tail} = decode_type_data(type, tail)
          [Map.put(member, :value, value) | acc]
        rescue
          _ ->
            acc
        end

      %{type: type, offset: offset, array_length: length} = member, acc ->
        <<_offset::binary(offset, 8), data::binary()>> = data

        {values, _} =
          Enum.reduce(1..length, {[], data}, fn _, {values, data} ->
            {value, data} = decode_type_data(type, data)
            {[value | values], data}
          end)

        [Map.put(member, :value, values) | acc]
    end)
    |> Enum.reverse()
  end

  def decode(<<type::binary(2, 8), data::binary()>>, _t) do
    Symbol.type_decode(type)
    |> decode_type(data)
  end

  def decode("", _t) do
    :invalid
  end

  def decode_type(_, _, _ \\ [])
  def decode_type(_type, <<>>, [acc]), do: acc
  def decode_type(_type, <<>>, [_ | _] = acc), do: Enum.reverse(acc)

  def decode_type(type, data, acc) do
    {value, tail} = decode_type_data(type, :binary.copy(data))
    decode_type(type, tail, [value | acc])
  end

  def decode_type_data(:bool, <<0x01, tail::binary>>), do: {true, tail}
  def decode_type_data(:bool, <<0xFF, tail::binary>>), do: {true, tail}
  def decode_type_data(:bool, <<0x00, tail::binary>>), do: {false, tail}
  def decode_type_data(:bool, <<1::size(1), tail::binary>>), do: {true, tail}
  def decode_type_data(:bool, <<0::size(1), tail::binary>>), do: {false, tail}
  def decode_type_data(:int, <<value::int, tail::binary>>), do: {value, tail}
  def decode_type_data(:sint, <<value::sint, tail::binary>>), do: {value, tail}
  def decode_type_data(:dint, <<value::dint, tail::binary>>), do: {value, tail}
  def decode_type_data(:lint, <<value::lint, tail::binary>>), do: {value, tail}
  def decode_type_data(:usint, <<value::usint, tail::binary>>), do: {value, tail}
  def decode_type_data(:uint, <<value::uint, tail::binary>>), do: {value, tail}
  def decode_type_data(:udint, <<value::udint, tail::binary>>), do: {value, tail}
  def decode_type_data(:ulint, <<value::ulint, tail::binary>>), do: {value, tail}
  def decode_type_data(:real, <<value::real, tail::binary>>), do: {value, tail}
  def decode_type_data(:lreal, <<value::lreal, tail::binary>>), do: {value, tail}

  def decode_type_data(:string, <<length::udint, value::binary(length, 8), tail::binary>>),
    do: {value, tail}

  def decode_type_data(:dword, <<value::binary(4, 8), tail::binary()>>),
    do: {:binary.copy(value), tail}

  def decode_type_data(_, <<0x00::uint, tail::binary>>), do: {nil, tail}
  def decode_type_data(_type, data), do: {data, <<>>}
end
