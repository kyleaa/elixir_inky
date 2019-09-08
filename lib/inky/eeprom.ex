defmodule Inky.EEPROM do
  require Logger
  alias Circuits.I2C
  @colors [:none, :black, :red, :yellow]
  def read() do
    {:ok, ref} = I2C.open("i2c-1")

    {:ok, resp} = I2C.write_read(ref, 0x50, <<0, 0>>, 29)
    Logger.warn(inspect(resp))
    decode(resp)
  end

  def decode(
        <<width::little-16, height::little-16, color_index::size(8), pcb_variant::size(8),
          display_variant::size(8)>> <> write_time
      ) do
    Logger.warn(color_index)

    %{
      width: width,
      height: height,
      color: decode_color(color_index),
      pcb_variant: pcb_variant,
      display_variant: display_variant,
      write_time: write_time
    }
  end

  def decode_color(i), do: Enum.at(@colors, i)
end
