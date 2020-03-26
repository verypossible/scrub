defmodule Scrub.CIP.Template do
  import Scrub.BinaryUtils, warn: false

  alias Scrub.CIP
  alias Scrub.CIP.Symbol

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
    case String.split(data, <<0x3B>>, parts: 2) do
      [member_info, member_names] ->

        member_info_list = :binary.bin_to_list(member_info)

        {template_name, member_info} =
          Enum.reverse(member_info_list)
          |> Enum.split_while(&String.printable?(<<&1>>))

        template_name = Enum.reverse(template_name)
        member_info =
          member_info
          |> Enum.reverse()
          |> :binary.list_to_bin()

        member_info = decode_member_info(member_info, [])
        [_magic | member_names] = String.split(member_names, <<0x00>>)

        members =
          Enum.zip(member_names, member_info)
          |> Enum.map(&Map.put(elem(&1, 1), :name, elem(&1, 0)))

        payload = %{
          template_name: to_string(template_name),
          members: members
        }

        {:ok, payload}

      _ ->
        {:error, :broken}
    end
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

  defp decode_member_info(<<>>, acc), do: acc
  defp decode_member_info(member_info, acc) do
    {member_info, tail} = decode_member_info(member_info)
    decode_member_info(tail, [member_info | acc])
  end

  defp decode_member_info(<<array_size :: uint, type :: binary(2, 8), offset :: udint, tail :: binary>>) do
    {Map.merge(%{array_size: array_size, offset: offset}, Symbol.type(type)), tail}
  end

end
