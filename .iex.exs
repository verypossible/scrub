defmodule PLC do
  alias Scrub.Session
  alias Scrub.CIP.ConnectionManager

  def start do
    {:ok, session} = Session.start_link("20.0.0.70")
    Process.unlink(session)

    data = ConnectionManager.encode_service(:large_forward_open)
    {:ok, resp} = Session.send_rr_data(session, data)
    {:ok, %{orig_network_id: conn}} = ConnectionManager.decode(resp)

    {session, conn}
  end

  def stop do
    Session.close(__MODULE__)
  end

  def run do
    {session, conn} = start()
    request_tag(session, conn, "REG_PWRUP_MEM")
  end

  def request_tag(session, conn, path) do
    data = ConnectionManager.encode_service(:unconnected_send, request_path: path)
    {:ok, resp} = Session.send_unit_data(session, conn, data)
    ConnectionManager.decode(resp)
  end

  def test_speed do
    {session, conn} = start()
    :timer.tc(fn () ->
      Enum.each(1..10_000, fn(_) ->
        request_tag(session, conn, "REG_PWRUP_MEM")
      end)
    end)
  end

  def multi_speed(tags, sched) do\
    shard = (tags / sched) |> floor()
    Enum.reduce(1..sched, [], fn(_, acc) -> [start() | acc] end)
    |> Enum.each(fn({session, conn}) ->
      spawn(fn ->
        :timer.tc(fn () ->
          Enum.each(1..shard, fn(_) ->
            request_tag(session, conn, "REG_PWRUP_MEM")
          end)
        end) |> IO.inspect
      end)
    end)
  end
end
