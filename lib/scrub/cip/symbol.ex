defmodule Scrub.CIP.Symbol do
  import Scrub.BinaryUtils, warn: false

  alias Scrub.CIP
  alias Scrub.CIP.Type

  @services [
    get_instance_attribute_list: 0x55
  ]

  def encode_service(:get_instance_attribute_list, opts \\ []) do
    instance_id = opts[:instance_id] || 0
    class = opts[:class] || 0x6B

    request_words = 3
    request_path = <<
      0x20, class, 0x25, 0x00, instance_id :: uint
    >>

    request_data = <<
      0x02, 0x00, 0x01, 0x00, 0x02, 0x00
    >>

    <<
      0::size(1),
      Keyword.get(@services, :get_instance_attribute_list)::size(7),
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

  defp decode_service(:get_instance_attribute_list, %{status: status}, data) do
    payload = %{
      status: status,
      tags: decode_tags(data, [])
    }
    {:ok, payload}
  end

  defp decode_tags(<<instance_id :: udint, name_len :: uint, name :: binary(name_len, 8), type :: binary(2, 8), tail :: binary>>, tags) do
    decode_tags(tail, [%{name: name, type: Type.decode(type), instance_id: instance_id} | tags])
  end

  defp decode_tags(<<>>, tags), do: Enum.reverse(tags)
end
