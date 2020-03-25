defmodule Scrub.CIP.Template do
  import Scrub.BinaryUtils, warn: false

  alias Scrub.CIP

  @services [
    get_attribute_list: 0x03,
    read_template_service: 0x4C
  ]

  def encode_service(_, _ \\ [])
  def encode_service(:get_attribute_list, opts) do
    instance_id = opts[:instance_id] || 0
    class = opts[:class] || 0x6C

    request_words = 3
    request_path = <<
      0x20, class, 0x25, 0x00, instance_id :: binary
    >>

    request_data = <<
      0x04, 0x00, 0x04, 0x00, 0x05, 0x00, 0x02, 0x00, 0x01, 0x00
    >>

    <<
      0::size(1),
      Keyword.get(@services, :get_attribute_list)::size(7),
      request_words :: usint,
      request_path :: binary,
      request_data :: binary
    >>
  end

  def encode_service(:read_template_service, opts) do
    instance_id = opts[:instance_id] || 0
    class = opts[:class] || 0x6C
    bytes = opts[:bytes]

    request_words = 3
    request_path = <<
      0x20, class, 0x25, 0x00, instance_id :: binary
    >>

    request_data = <<
      0x00 :: udint,
      bytes :: uint
    >>

    <<
      0::size(1),
      Keyword.get(@services, :read_template_service)::size(7),
      request_words :: usint,
      request_path :: binary,
      request_data :: binary
    >>
  end

  def decode(<<1::size(1), service::size(7), 0, status_code::usint, size::usint, data::binary>>) do
    <<service>> = <<0::size(1), service::size(7)>>

    header = %{
      status: CIP.status_code(status_code),
      size: size
    }

    case Enum.find(@services, &(elem(&1, 1) == service)) do
      nil ->
        {:error, {:not_implemented, data}}

      {service, _} ->
        decode_service(service, header, data)
    end
  end

  defp decode_service(:get_attribute_list, %{status: status}, <<_count :: uint, attributes :: binary>>) do
    {:ok, decode_attributes(attributes, [])}
  end

  defp decode_service(:read_template_service, %{status: status}, data) do
    {:ok, data}
  end

  defp decode_attributes(<<>>, acc), do: Enum.into(acc, %{})
  defp decode_attributes(attributes, acc) do
    {attribute, tail} = decode_attribute(attributes)
    decode_attributes(tail, [attribute | acc])
  end

  defp decode_attribute(<<0x04 :: uint, status :: uint, definition_size :: udint, tail :: binary>>) do
    {{:definition_size, definition_size}, tail}
  end

  defp decode_attribute(<<0x05 :: uint, status :: uint, structure_size :: udint, tail :: binary>>) do
    {{:structure_size, structure_size}, tail}
  end

  defp decode_attribute(<<0x02 :: uint, status :: uint, member_count :: uint, tail :: binary>>) do
    {{:member_count, member_count}, tail}
  end

  defp decode_attribute(<<0x01 :: uint, status :: uint, crc :: uint, tail :: binary>>) do
    {{:crc, crc}, tail}
  end
end
