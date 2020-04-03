defmodule Scrub.CIP.Connection do
  defstruct [
    serial: nil,
    orig_network_id: nil,
    target_network_id: nil,
    orig_api: nil,
    target_api: nil
  ]
end
