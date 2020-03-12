defmodule PLCTest do
  use ExUnit.Case
  doctest PLC

  test "greets the world" do
    assert PLC.hello() == :world
  end
end
