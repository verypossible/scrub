defmodule Scrub.CIP do
  def status_code(0x00), do: :success
  def status_code(_), do: :error
end
