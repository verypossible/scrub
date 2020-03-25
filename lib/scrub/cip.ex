defmodule Scrub.CIP do
  def status_code(0x00), do: :success
  def status_code(0x06), do: :too_much_data
  def status_code(status), do: status

end
