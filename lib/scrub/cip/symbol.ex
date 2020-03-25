defmodule Scrub.CIP.Symbol do
  import Scrub.BinaryUtils, warn: false

  alias Scrub.CIP

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
    tag = Map.merge(%{name: name, instance_id: instance_id}, type(type))
    decode_tags(tail, [tag | tags])
  end

  defp decode_tags(<<>>, tags), do: Enum.reverse(tags)

  def type(<<type :: binary(12, 1), reserved :: size(1), array_dims :: size(2), structure :: size(1)>>) do
    %{
      structure: type_structure(structure, reserved),
      array_dims: array_dims,
      type: type
    }
  end

  #   type_structure(structure, reserved)
  def type_structure(_, 1), do: :system
  def type_structure(0, 0), do: :atomic
  def type_structure(1, 0), do: :structured

  def filter(tags) when is_list(tags) do
    tags
    # |> Enum.reject(& &1.structure == :atomic && &1.type not in 0x001..0x0FF)
    # |> Enum.reject(& &1.structure == :structured && &1.type not in 0x100..0xEFF)
    |> Enum.reject(& &1.structure == :system)
    |> Enum.reject(& String.starts_with?(&1.name, "__"))
    |> Enum.reject(& String.contains?(&1.name, ":"))
  end

  def filter() do

  end

end
