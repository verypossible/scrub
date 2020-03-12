defmodule PLC.Session do
  import PLC.BinaryUtils, warn: false

  @encapsulation_header_length 24
  @encapsulation_commands [
    register_session: 0x65,
    unregister_session: 0x66,
  ]

  @doc """
  2-3.1 Encapsulation Packet Structure
  """
  def encapsulation_header(command, length, session_handle, status, context, options) do
    command = Keyword.get(@encapsulation_commands, command)
    <<
      command :: uint16,
      length :: uint16,
      session_handle :: uint32,
      status :: uint32,
      context :: uint64,
      options :: uint32,
    >>
  end

  def encapsulation_header_length(), do: @encapsulation_header_length

  def register() do
    protocol_version = 1
    options = 0

    data = <<
      protocol_version :: uint16,
      options :: uint16
    >>

    encapsulation_header(:register_session, byte_size(data), 0, 0, 0, 0) <> data
  end

  def unregister(session_handle) do
    encapsulation_header(:register_session, 0, session_handle, 0, 0, 0) <> <<>>
  end

  def register_reply(<<0x65 :: uint16, 4 :: uint16, session_handle :: uint32, _context :: uint64, 0 :: uint32, _command :: binary>>) do
    {:ok, session_handle}
  end

  def register_reply(packet) do
    IO.inspect packet
    :error
  end
end
