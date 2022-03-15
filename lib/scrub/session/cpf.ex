defmodule Scrub.Session.CPF do
  @moduledoc """
  2-6 Common Packet Format
  """

  import Scrub.BinaryUtils

  # 2-6.3 Item ID Numbers
  @item_ids [
    null: 0x00,
    connected_address: 0xA1,
    sequenced_address: 0x8002,
    unconnected_data: 0xB2,
    connected_data: 0xB1
  ]

  def encode(:connected_data, payload, sequence_number) do
    <<
      Keyword.get(@item_ids, :connected_data)::uint,
      # TODO: Not sure why I needed to att 2 to this?
      byte_size(payload) + 2::uint,
      # CIP Sequence Count
      sequence_number::uint,
      payload::binary
    >>
  end

  def encode(item_id, payload) when is_atom(item_id) do
    case Keyword.get(@item_ids, item_id) do
      nil ->
        {:error, :unknown_cpf_type}

      type_id ->
        size = byte_size(payload)

        <<
          type_id::uint,
          size::uint
        >> <>
          if size > 0, do: payload, else: <<>>
    end
  end

  def decode(<<_handle::udint, _timeout::uint, item_count::uint, data::binary>>) do
    resp =
      Enum.reduce(1..item_count, {[], data}, fn _, {items, data} ->
        {item, tail} = decode_item(data)
        {[item | items], tail}
      end)

    case resp do
      {items, ""} -> {:ok, items}
      resp -> {:error, resp}
    end
  end

  def decode(other) do
    {:error, other}
  end

  defp decode_item(<<0xB1::uint, size::uint, item_data::binary(size, 8), tail::binary>>) do
    <<_sequence_number::uint, item_data::binary>> = item_data
    {{:connected_data, item_data}, tail}
  end

  defp decode_item(<<item_id::uint, size::uint, item_data::binary(size, 8), tail::binary>>) do
    case Enum.find(@item_ids, &(elem(&1, 1) == item_id)) do
      nil ->
        {:error, :not_implemented, tail}

      {item_id, _} ->
        {{item_id, item_data}, tail}
    end
  end
end
