defmodule ScrubTest do
  use ExUnit.Case
  alias Scrub.CIP.Connection


  doctest Scrub
  @plc_address "20.0.0.70"


  @tag :with_plc
  test "can open a connection" do
    {:ok, session} =
      Scrub.open_session(@plc_address)
    :ok = wait_for_session(session)
    assert {_, %Connection{ }} = Scrub.open_conn(session)
  end

  @tag :with_plc
  test "can receive retrieve a tag" do
    {:ok, session} =
      Scrub.open_session(@plc_address)
    :ok = wait_for_session(session)
    assert {:ok, _} = Scrub.read_tag(session,"P1_HMI_INK_DINT_ARRAY3")
  end

  @tag :with_plc
  test "can close a session" do
    {:ok, session} =
      Scrub.open_session(@plc_address)
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
