defmodule ScrubTest do
  use ExUnit.Case
  alias Scrub.CIP.Connection

  doctest Scrub
  use ExUnit.Case, async: false
  setup_all do
    {:ok, session} =
      Scrub.open_session("20.0.0.70")
      :ok = wait_for_session(session)
    %{session: session}
  end

  test "can open a connection", %{session: session} do
    assert {_, %Connection{ }} = Scrub.open_conn(session)
  end

  test "can receive retrieve a tag", %{session: session} do
    assert {:ok, _} = Scrub.read_tag(session,"P1_HMI_INK_DINT_ARRAY3")
  end


  test "can close a session", %{session: _} do
    {:ok, session} =
      Scrub.open_session("20.0.0.70")
      :ok = wait_for_session(session)
    assert {:ok, _ } = Scrub.close_session(session)

  end


  defp wait_for_session(session) do
    case Scrub.check_conn_status(session) do
      :error -> wait_for_session(session)
      :idle ->
        :ok
    end
  end
end
