defmodule Scrub.CIP.ConnectionManager do
  import Scrub.BinaryUtils

  alias Scrub.CIP
  alias Scrub.CIP.Type
  alias Scrub.CIP.Connection

  @services [
    large_forward_open: 0x5B,
    forward_close: 0x4E,
    read_tag_service: 0x4C,
    multiple_service_request: 0x0A
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

  def encode_service(:multiple_service_request, opts) do
    service_count = Enum.count(opts[:tag_list])
    offset_start = service_count * 2 + 2

    {service_offsets, service_list} =
      Enum.reduce_while(
        opts[:tag_list],
        {1, offset_start, <<offset_start::uint>>, <<>>},
        fn request_path, {idx, offset_counter, offset_bin, service_acc} ->
          service = encode_service(:read_tag_service, request_path: request_path)
          # make sure that we dont create an offset for the last service
          if idx < service_count do
            offset_counter = offset_counter + byte_size(service)

            {:cont,
             {idx + 1, offset_counter, <<offset_bin::binary, offset_counter::uint>>,
              <<service_acc::binary, service::binary>>}}
          else
            {:halt, {offset_bin, <<service_acc::binary, service::binary>>}}
          end
        end
      )

    <<
      0::size(1),
      Keyword.get(@services, :multiple_service_request)::size(7),
      # Request Path Size
      0x02,
      # message router path
      0x20,
      0x02,
      0x24,
      0x01,
      service_count::uint,
      # first offset is always the same
      service_offsets::binary,
      service_list::binary
    >>
  end

  def encode_service(:read_tag_service, opts) do
    request_path = encode_request_path(opts[:request_path])

    request_words = (byte_size(request_path) / 2) |> floor

    read_elements = opts[:read_elements] || 1

    <<
      0::size(1),
      Keyword.get(@services, :read_tag_service)::size(7),
      request_words::usint,
      request_path::binary,
      read_elements::uint
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

    <<0x91, byte_size(request_path)::usint, request_path_padded::binary>>
  end

  def encode_request_path(request_path) when is_integer(request_path) do
    <<0x28, request_path::size(8)>>
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
         :read_tag_service,
         %{status_code: :success},
         <<
           data::binary
         >>,
         template
       ) do
    case Type.decode(data, template) do
      :invalid -> {:error, :invalid}
      value -> {:ok, value}
    end
  end

  defp decode_service(
         :multiple_service_request,
         %{status_code: code},
         <<
           service_count::uint,
           offset_bin::binary(service_count, 16),
           data::binary
         >>,
         _template
       )
       when code in [:success, :embedded_service_failure] do
    # grab offset data
    offset_list =
      for <<offset::uint <- offset_bin>> do
        offset
      end

    {start, offset_list} = List.pop_at(offset_list, 0)

    {service_data, last_service, _} =
      Enum.reduce(offset_list, {[], data, start}, fn offset, {data_list, data, previous_offset} ->
        size = offset - previous_offset
        <<important_data::binary(size, 8), rest::binary>> = data
        {[important_data | data_list], rest, offset}
      end)

    # combine the final service into the list
    service_data = [last_service | service_data]

    final_output =
      Enum.map(service_data, fn s ->
        case decode(s) do
          {:ok, value} -> value
          error -> error
        end
      end)
      |> Enum.reverse()

    {:ok, final_output}
  end

  defp decode_service(
         _,
         %{status_code: code},
         _,
         _
       ) do
    {:error, code}
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
    dir = opts[:dir] || :server
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
