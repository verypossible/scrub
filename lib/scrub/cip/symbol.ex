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
          type: type_decode(<<type_l :: little - binary(8, 1), 0 :: size(4), type_h :: little - binary(4, 1)>>)
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
    |> Enum.reject(& String.contains?(&1.name, ":"))
    |> Enum.reject(& filter_structure/1)
  end

  def filter_structure(%{structure: :atomic, type: {:unknown, _}}), do: true
  def filter_structure(%{structure: :system}), do: true
  def filter_structure(%{name: <<"__", _tail :: binary>>}), do: true
  def filter_structure(%{structure: :structured, template_instance: instance}) do
    <<instance :: uint>> = instance
    instance not in 0x100..0xEFF
  end
  def filter_structure(_), do: false

  def type_decode(<<0xC1, _>>), do: :bool
  def type_decode(<<0xC3, _>>), do: :int
  def type_decode(<<0xC2, _>>), do: :sint
  def type_decode(<<0xC4, _>>), do: :dint
  def type_decode(<<0xC5, _>>), do: :lint
  def type_decode(<<0xC6, _>>), do: :usint
  def type_decode(<<0xC7, _>>), do: :uint
  def type_decode(<<0xC8, _>>), do: :udint
  def type_decode(<<0xC9, _>>), do: :ulint
  def type_decode(<<0xCA, _>>), do: :real
  def type_decode(<<0xCB, _>>), do: :lreal
  def type_decode(<<0xCC, _>>), do: :stime
  def type_decode(<<0xCD, _>>), do: :date
  def type_decode(<<0xCE, _>>), do: :time_of_day
  def type_decode(<<0xCF, _>>), do: :date_and_time
  def type_decode(<<0xD0, _>>), do: :string
  def type_decode(<<0xD1, _>>), do: :byte
  def type_decode(<<0xD2, _>>), do: :word
  def type_decode(<<0xD3, _>>), do: :dword
  def type_decode(<<0xD4, _>>), do: :lword
  def type_decode(<<0xD5, _>>), do: :string2
  def type_decode(<<0xD6, _>>), do: :ftime
  def type_decode(<<0xD7, _>>), do: :ltime
  def type_decode(<<0xD8, _>>), do: :itime
  def type_decode(<<0xD9, _>>), do: :stringn
  def type_decode(<<0xDA, _>>), do: :short_string
  def type_decode(<<0xDB, _>>), do: :time
  def type_decode(<<0xDC, _>>), do: :epath
  def type_decode(<<0xDD, _>>), do: :engunit
  def type_decode(<<0xDE, _>>), do: :stringi

  def type_decode(bits), do: {:unknown, bits}
end
