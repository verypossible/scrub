defmodule Scrub.CIP.Type do
  import Scrub.BinaryUtils, warn: false

  alias Scrub.CIP.Symbol

  def decode(<<0xA0, 0x02, _crc :: uint, data :: binary>>, %{members: members} = structure) do
    IO.puts "Template: #{structure.template_name}"
    result =
      Enum.reduce(members, {nil, data, []}, fn
        %{name: <<"ZZZZZZZZZZ", _ :: binary>>} = host, {_, data, acc} ->
          {host, data, acc}

        %{type: {:bool, _}} = member, {%{} = host, <<bool :: binary(1), tail :: binary>>, acc} ->
          {host, tail, [Map.put(member, :value, decode({:bool, 0}, <<bool :: binary(1, 8)>>)) | acc]}

        %{type: type, array_dims: 0} = member, {_, data, acc} ->
          {value, tail} = decode_type(type, data)
          {nil, tail, [Map.put(member, :value, value) | acc]}

        %{type: type, array_dims: dims, array_length: length} = member, {_, data, acc} ->
          {value, tail} =
            Enum.reduce(1..dims, {[], data}, fn(_, {values, data}) ->
              {value, tail} =
                Enum.reduce(1..length, {<<>>, data}, fn(pos, {value, data}) ->
                  IO.inspect pos
                  {more, tail} = decode_type(type, data)
                  {value <> more, tail}
                end)
              {[value | values], tail}
            end)
          {nil, tail, [Map.put(member, :value, value)]}
      end)
    case result do
      {_, "", structure} -> structure
      {_, tail, structure} -> {structure, tail}
    end
  end

  def decode(data, _t) do
    type = Symbol.type_decode(data)
    case decode_type(type, data) do
      {data, <<>>} -> data
      more_data -> more_data
    end
  end
  def decode_type({:bool, _}, <<0x00::uint, tail :: binary>>), do: {false, tail}
  def decode_type({:bool, _}, <<0x01::uint, tail :: binary>>), do: {true, tail}
  def decode_type(:real, <<0x00, value::real, tail :: binary>>), do: {value, tail}
  def decode_type(:dword, <<value :: binary(4, 8), tail :: binary()>>), do: {value, tail}
  def decode_type(_, <<0x00::uint, tail :: binary>>), do: {nil, tail}
end
