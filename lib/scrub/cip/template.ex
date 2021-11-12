defmodule Scrub.CIP.Template do
  import Scrub.BinaryUtils, warn: false
  alias Scrub.CIP
  alias Scrub.CIP.Symbol

  @services [
    get_attribute_list: 0x03,
    get_attribute_list_reply: 0x83,
    read_template_service: 0x4C,
    read_template_service_reply: 0xCC
  ]

  def encode_service(_, _ \\ [])

  def encode_service(:get_attribute_list, opts) do
    instance_id = opts[:instance_id] || 0
    class = opts[:class] || 0x6C

    request_words = 3

    request_path = <<
      0x20,
      class,
      0x25,
      0x00,
      instance_id::binary
    >>

    request_data = <<
      0x04,
      0x00,
      0x04,
      0x00,
      0x05,
      0x00,
      0x02,
      0x00,
      0x01,
      0x00
    >>

    <<
      0::size(1),
      Keyword.get(@services, :get_attribute_list)::size(7),
      request_words::usint,
      request_path::binary,
      request_data::binary
    >>
  end

  def encode_service(:read_template_service, opts) do
    instance_id = opts[:instance_id] || 0
    class = opts[:class] || 0x6C
    bytes = opts[:bytes]
    offset = opts[:offset] || 0

    request_words = 3

    request_path = <<
      0x20,
      class,
      0x25,
      0x00,
      instance_id::binary
    >>

    request_data = <<
      offset::udint,
      bytes::uint
    >>

    <<
      0::size(1),
      Keyword.get(@services, :read_template_service)::size(7),
      request_words::usint,
      request_path::binary,
      request_data::binary
    >>
  end

  def decode(
        <<service, 0, status_code::usint, ext_status_size::usint, _::binary(ext_status_size, 16),
          data::binary>> = payload,
        meta \\ %{},
        additional_data \\ <<>>
      ) do
    meta = Map.merge(meta, %{status: CIP.status_code(status_code)})

    case Enum.find(@services, &(elem(&1, 1) == service)) do
      nil ->
        {:error, {:not_implemented, payload}}

      {service, _} ->
        decode_service(service, meta, additional_data <> data)
    end
  end

  def decode_service(_, %{status: :too_much_data}, data) do
    {:partial_data, data}
  end

  def decode_service(
        :get_attribute_list_reply,
        %{status: :success},
        <<_count::uint, attributes::binary>>
      ) do
    {:ok, decode_attributes(attributes)}
  end

  def decode_service(
        :read_template_service_reply,
        %{status: :success, member_count: member_count},
        data
      ) do
    template = decode_template(member_count, data)
    {:ok, template}
  end

  defp decode_attributes(binary, acc \\ %{})
  defp decode_attributes(<<>>, acc), do: acc

  defp decode_attributes(<<0x04::uint, _status::uint, def_size::udint, tail::binary>>, acc) do
    decode_attributes(tail, Map.put(acc, :definition_size, def_size))
  end

  defp decode_attributes(<<0x05::uint, _status::uint, struct_size::udint, tail::binary>>, acc) do
    decode_attributes(tail, Map.put(acc, :structure_size, struct_size))
  end

  defp decode_attributes(<<0x02::uint, _status::uint, member_count::uint, tail::binary>>, acc) do
    decode_attributes(tail, Map.put(acc, :member_count, member_count))
  end

  defp decode_attributes(<<0x01::uint, _status::uint, crc::uint, tail::binary>>, acc) do
    decode_attributes(tail, Map.put(acc, :crc, crc))
  end

  defp decode_template(member_count, bin) do
    <<member_info::binary(member_count, 64), names::binary>> = bin
    member_info = decode_member_info(member_info)
    [template_name | member_names] = String.split(names, <<0x00>>)

    members =
      Enum.zip([member_info, member_names])
      |> Enum.flat_map(fn
        {info, ""} ->
          # hidden member
          []

        {info, name} ->
          [Map.put(info, :name, name)]
      end)

    %{template_name: template_name, members: members}
  end

  defp decode_member_info(binary, acc \\ [])
  defp decode_member_info(<<>>, acc), do: Enum.reverse(acc)
  defp decode_member_info(<<0, 0>>, []), do: [%{type: :unknown, offset: 0}]

  defp decode_member_info(
         <<len_or_loc::uint, type::binary(2, 8), offset::udint, tail::binary>>,
         acc
       ) do
    member =
      case Symbol.type_decode(type) do
        :bool ->
          %{type: :bool, offset: offset, bit_location: len_or_loc}

        other_type ->
          %{type: other_type, offset: offset, array_length: len_or_loc}
      end

    decode_member_info(tail, [member | acc])
  end
end
