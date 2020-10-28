defmodule Scrub.CIP do
  def status_code(0x00), do: :success
  def status_code(0x03), do: :invalid_parameter
  def status_code(0x04), do: :path_segment_error
  def status_code(0x05), do: :path_unknown
  def status_code(0x06), do: :too_much_data
  def status_code(0x0A), do: :get_attribute_error
  def status_code(0x11), do: :too_much_data_failure
  def status_code(0x0F), do: :privilege_violation
  def status_code(status), do: status
end
