defmodule Scrub.Session.Protocol do
  @moduledoc """
  EtherNet/IP Protocol
  """

  import Scrub.BinaryUtils

  alias Scrub.Session.CPF
  alias Scrub.CIP.Connection

  @encapsulation_header_length 24
  @encapsulation_commands [
    nop: 0x00,
    list_services: 0x04,
    list_identity: 0x63,
    list_interfaces: 0x64,
    register_session: 0x65,
    unregister_session: 0x66,
    send_rr_data: 0x6F,
    send_unit_data: 0x70
  ]

  # 2-3.1 Encapsulation Packet Structure
  def encapsulation_header(command, length, session_handle, status, context, options) do
    command = Keyword.get(@encapsulation_commands, command)

    <<
      command::uint,
      length::uint,
      session_handle::udint,
      status::udint,
      context::ulint,
      options::udint
    >>
  end

  def encapsulation_header_length(), do: @encapsulation_header_length

  @doc """
  2-4.4 RegisterSession
  """
  def register() do
    protocol_version = 1
    options = 0

    data = <<
      protocol_version::uint,
      options::uint
    >>

    encapsulation_header(:register_session, byte_size(data), 0, 0, 0, 0) <> data
  end

  def unregister(session_handle) do
    encapsulation_header(:unregister_session, 0, session_handle, 0, 0, 0) <> <<>>
  end

  @doc """
  2-4.7 SendRRData
  """
  def send_rr_data(session_handle, payload, timeout \\ 65_535) do
    data = <<
      0x00::udint,
      timeout::uint,
      2::udint,
      CPF.encode(:null, <<0x00>>)::binary(2, 8),
      CPF.encode(:unconnected_data, payload)::binary
    >>

    encapsulation_header(:send_rr_data, byte_size(data), session_handle, 0, 0, 0) <> data
  end

  @doc """
  2-4.8 SendUnitData
  """
  def send_unit_data(
        session_handle,
        %Connection{orig_network_id: network_id},
        sequence_number,
        payload,
        timeout \\ 65_535
      ) do
    data = <<
      0x00::udint,
      timeout::uint,
      2::uint,
      CPF.encode(:connected_address, network_id)::binary,
      CPF.encode(:connected_data, payload, sequence_number)::binary
    >>

    encapsulation_header(:send_unit_data, byte_size(data), session_handle, 0, 0, 0) <> data
  end

  def decode(
        <<cmd::uint, length::uint, session_handle::udint, status::udint, context::ulint,
          options::udint, data::binary>>
      ) do
    header = %{
      cmd: cmd,
      length: length,
      session_handle: session_handle,
      status: status,
      context: context,
      options: options
    }

    cond do
      byte_size(data) < length ->
        :partial

      true ->
        decode(header, data)
    end
  end

  def decode(data) do
    {:error, :malformed_packet, data}
  end

  def decode(%{cmd: cmd} = header, data) do
    case Enum.find(@encapsulation_commands, &(elem(&1, 1) == cmd)) do
      nil ->
        {:error, {:unknown_command, cmd}}

      {cmd, _} ->
        decode(cmd, header, data)
    end
  end

  def decode(:send_rr_data, _header, data) do
    case CPF.decode(data) do
      # ¯\_(ツ)_/¯
      {:ok, items} -> Keyword.fetch(items, :unconnected_data)
      error -> error
    end
  end

  def decode(:register_session, %{session_handle: session_handle}, _data) do
    {:ok, session_handle}
  end

  def decode(:send_unit_data, _header, data) do
    case CPF.decode(data) do
      {:ok, items} -> Keyword.fetch(items, :connected_data)
      error -> error
    end
  end
end
