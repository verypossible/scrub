defmodule Scrub.CIP.ConnectionManager do
  import Scrub.BinaryUtils, warn: false

  alias Scrub.CIP
  alias Scrub.CIP.Type
  alias Scrub.CIP.Connection

  @services [
    large_forward_open: 0x5B,
    forward_close: 0x4E,
    unconnected_send: 0x4C
  ]

  def encode_service(_, _opts \\ [])

  def encode_service(:large_forward_open, opts) do
    priority = opts[:priority] || 0
    time_ticks = opts[:time_ticks] || 10
    timeout_ticks = opts[:timeout_ticks] || 5

    orig_conn_id = 0x00
    <<target_conn_id::udint>> = :crypto.strong_rand_bytes(4)
    <<conn_serial::uint>> = :crypto.strong_rand_bytes(2)

    orig_rpi = opts[:orig_rpi] || 1_000_000

    orig_network_conn_params =
      opts[:orig_network_conn_params] || large_forward_open_network_parameters()

    target_rpi = opts[:target_rpi] || 1_000_000

    target_network_conn_params =
      opts[:target_network_conn_params] || large_forward_open_network_parameters()

    transport_class_trigger = opts[:transport_class_trigger] || transport_class_trigger()

    <<0::size(1), Keyword.get(@services, :large_forward_open)::size(7), 0x02, 0x20, 0x06, 0x24,
      0x01>> <>
      <<
        # Time_ticks/ Priority
        # Reserved
        0::little-size(3),
        priority::little-size(1),
        time_ticks::little-size(4),
        timeout_ticks::usint,
        # Connection information
        orig_conn_id::udint,
        target_conn_id::udint,
        conn_serial::uint,
        # Vendor Info

        Scrub.vendor()::binary,
        Scrub.serial_number()::binary,

        # # Connection timeout multiplier
        1::usint,
        # # Reserved
        0x00,
        0x00,
        0x00,
        # # Packet info
        orig_rpi::udint,
        orig_network_conn_params::binary(4, 8),
        target_rpi::udint,
        target_network_conn_params::binary(4, 8),
        transport_class_trigger::binary(1),
        # Connection path to Message Router
        # size
        0x03,
        # seg 1
        0x01,
        0x00,
        # seg 2
        0x20,
        0x02,
        # seg 3
        0x24,
        0x01
      >>
  end

  def encode_service(:forward_close, opts) do
    priority = opts[:priority] || 0
    time_ticks = opts[:time_ticks] || 10
    timeout_ticks = opts[:timeout_ticks] || 5
    conn_serial = opts[:conn].serial

    <<0::size(1), Keyword.get(@services, :forward_close)::size(7), 0x02, 0x20, 0x06, 0x24, 0x01>> <>
      <<
        # Time_ticks/ Priority
        # Reserved
        0::little-size(3),
        priority::little-size(1),
        time_ticks::little-size(4),
        timeout_ticks::usint,
        # # Connection information
        conn_serial::binary(2, 8),
        # # Vendor Info

        Scrub.vendor()::binary,
        Scrub.serial_number()::binary,

        # # Connection path to Message Router
        0x03::usint,
        # Reserved
        0::usint,
        0x01,
        0x00,
        0x20,
        0x02,
        0x24,
        0x01
      >>
  end

  def encode_service(:unconnected_send, opts) do
    request_path = encode_request_path(opts[:request_path])

    request_words = (byte_size(request_path) / 2) |> floor

    read_elements = opts[:read_elements] || 1

    <<
      0::size(1),
      Keyword.get(@services, :unconnected_send)::size(7),
      request_words::usint,
      request_path::binary,
      read_elements::ulint
    >>
  end

  def encode_request_path(request_path) when is_binary(request_path) do
    request_size = byte_size(request_path)

    request_path_padding =
      case rem(request_size, 2) do
        0 -> 0
        num -> 2 - num
      end

    request_path_padded = <<request_path::binary, 0x00::size(request_path_padding)-unit(8)>>
    request_path = <<0x91, byte_size(request_path)::usint, request_path_padded::binary>>

    <<request_path::binary>>
  end

  def encode_request_path(request_path) when is_list(request_path) do
    Enum.reduce(request_path, <<>>, fn member, acc ->
      <<acc::binary, encode_request_path(member)::binary>>
    end)
  end

  def decode(
        <<1::size(1), service::size(7), 0, status_code::usint, size::usint, data::binary>>,
        template_or_tag \\ nil
      ) do
    <<service>> = <<0::size(1), service::size(7)>>

    header = %{
      status_code: CIP.status_code(status_code),
      size: size
    }

    case Enum.find(@services, &(elem(&1, 1) == service)) do
      nil ->
        {:error, {:not_implemented, data}}

      {service, _} ->
        decode_service(service, header, data, template_or_tag)
    end
  end

  # Large Forward Open
  defp decode_service(
         :large_forward_open,
         _header,
         <<
           orig_network_id::binary(4, 8),
           target_network_id::binary(4, 8),
           conn_serial::binary(2, 8),
           _orig_vendor_id::uint,
           _orig_serial::udint,
           orig_api::udint,
           target_api::udint,
           0::usint,
           _reserved::binary
         >>,
         _t
       ) do
    {:ok,
     %Connection{
       orig_network_id: orig_network_id,
       target_network_id: target_network_id,
       serial: conn_serial,
       orig_api: orig_api,
       target_api: target_api
     }}
  end

  defp decode_service(:forward_close, _header, data, _t) do
    {:ok, data}
  end

  defp decode_service(
         :unconnected_send,
         %{size: _size},
         <<
           data::binary
         >>,
         template
       ) do
    {:ok, Type.decode(data, template)}
  end

  defp large_forward_open_network_parameters(opts \\ []) do
    owner = opts[:owner] || 0
    connection_type = opts[:connection_type] || :point_to_point
    priority = opts[:priority] || :low
    fixed? = opts[:fixed] == true
    fixed = if fixed?, do: 0, else: 1
    connection_size = opts[:connection_size] || 4002

    <<
      connection_size::little-size(2)-unit(8),
      # reserved,
      0::size(8),
      owner::little-size(1),
      encode_connection_type(connection_type)::little-size(2),
      # reserved
      0::little-size(1),
      encode_priority(priority)::little-size(2),
      fixed::little-size(1),
      # reserved,
      0::size(1)
    >>
  end

  defp transport_class_trigger(opts \\ []) do
    dir = opts[:dir] || :client
    trigger = opts[:trigger] || :application_object
    transport_class = opts[:transport_class] || 3

    <<
      encode_transport_class_direction(dir)::size(1),
      encode_production_trigger(trigger)::little-size(3),
      transport_class::little-size(4)
    >>
  end

  defp encode_connection_type(:null), do: 0
  defp encode_connection_type(:multicast), do: 1
  defp encode_connection_type(:point_to_point), do: 2
  defp encode_connection_type(:reserved), do: 3

  defp encode_priority(:low), do: 0
  defp encode_priority(:high), do: 1
  defp encode_priority(:scheduled), do: 2
  defp encode_priority(:urgent), do: 3

  defp encode_transport_class_direction(:client), do: 0
  defp encode_transport_class_direction(:server), do: 1

  defp encode_production_trigger(:cyclic), do: 0
  defp encode_production_trigger(:change_of_state), do: 1
  defp encode_production_trigger(:application_object), do: 2
end
