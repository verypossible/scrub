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

  def type(<<type_l :: binary(8, 1), structure :: size(1), array_dims :: size(2), reserved :: size(1), type_h :: binary(4, 1)>>) do
    case type_structure(structure, reserved) do
      structure when structure in [:atomic, :system] ->
        %{
          structure: structure,
          array_dims: array_dims,
          type: type_decode(<<type_l :: little - binary(8, 1), type_h :: little - binary(4, 1)>>)
        }

      :structured ->
        %{
          structure: :structured,
          array_dims: array_dims,
          template_instance: <<type_l :: little - binary(8, 1), 0 :: size(4), type_h :: little - binary(4, 1),>>
        }
    end
  end

  #   type_structure(structure, reserved)
  def type_structure(_, 1), do: :system
  def type_structure(0, 0), do: :atomic
  def type_structure(1, 0), do: :structured

  def filter(tags) when is_list(tags) do
    tags
    |> Enum.reject(& &1.structure == :atomic && is_tuple(&1.type) && elem(&1.type, 0) == :unknown)
    # |> Enum.reject(& &1.structure == :structured && &1.type not in 0x100..0xEFF)
    |> Enum.reject(& &1.structure == :system)
    |> Enum.reject(& String.starts_with?(&1.name, "__"))
    |> Enum.reject(& String.contains?(&1.name, ":"))
  end

  def type_decode(<<0xC1, pos :: size(4)>>), do: {:bool, pos}
  def type_decode(<<0xC2, _ :: size(4)>>), do: :sint
  def type_decode(<<0xC3, _ :: size(4)>>), do: :int
  def type_decode(<<0xC4, _ :: size(4)>>), do: :dint
  def type_decode(<<0xC5, _ :: size(4)>>), do: :lint
  def type_decode(<<0xC6, _ :: size(4)>>), do: :usint
  def type_decode(<<0xC7, _ :: size(4)>>), do: :uint
  def type_decode(<<0xC8, _ :: size(4)>>), do: :udint
  def type_decode(<<0xC9, _ :: size(4)>>), do: :ulint
  def type_decode(<<0xCA, _ :: size(4)>>), do: :real
  def type_decode(<<0xCB, _ :: size(4)>>), do: :lreal
  def type_decode(<<0xCC, _ :: size(4)>>), do: :stime
  def type_decode(<<0xCD, _ :: size(4)>>), do: :date
  def type_decode(<<0xCE, _ :: size(4)>>), do: :time_of_day
  def type_decode(<<0xCF, _ :: size(4)>>), do: :date_and_time
  def type_decode(<<0xD0, _ :: size(4)>>), do: :string
  def type_decode(<<0xD1, _ :: size(4)>>), do: :byte
  def type_decode(<<0xD2, _ :: size(4)>>), do: :word
  def type_decode(<<0xD3, _ :: size(4)>>), do: :dword
  def type_decode(<<0xD4, _ :: size(4)>>), do: :lword
  def type_decode(<<0xD5, _ :: size(4)>>), do: :string2
  def type_decode(<<0xD6, _ :: size(4)>>), do: :ftime
  def type_decode(<<0xD7, _ :: size(4)>>), do: :ltime
  def type_decode(<<0xD8, _ :: size(4)>>), do: :itime
  def type_decode(<<0xD9, _ :: size(4)>>), do: :stringn
  def type_decode(<<0xDA, _ :: size(4)>>), do: :short_string
  def type_decode(<<0xDB, _ :: size(4)>>), do: :time
  def type_decode(<<0xDC, _ :: size(4)>>), do: :epath
  def type_decode(<<0xDD, _ :: size(4)>>), do: :engunit
  def type_decode(<<0xDE, _ :: size(4)>>), do: :stringi

  def type_decode(bits), do: {:unknown, bits}
end
