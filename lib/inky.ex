defmodule Inky do
  alias Circuits.{GPIO, SPI}

  # @reset_pin 13
  # @busy_pin 11
  # @dc_pin 15
  @reset_pin 27
  @busy_pin 17
  @dc_pin 22
  @valid_colors [:white, :black, :red, :yellow]

  def setup(config \\ %{}) do
    config =
      cond do
        config == %{} ->
          {:ok, busy_pin} = GPIO.open(@busy_pin, :input, pull_mode: :none)
          {:ok, reset_pin} = GPIO.open(@reset_pin, :output, pull_mode: :none)
          {:ok, dc_pin} = GPIO.open(@dc_pin, :output, pull_mode: :none)

          {:ok, spi} = SPI.open("spidev0.0", speed_hz: 488_000)
          eeprom = Inky.EEPROM.read()

          pixels = Matrix.zeros(eeprom.height, eeprom.width)

          {cols, rows, rot} =
            case eeprom do
              %{width: 400, height: 300} -> {400, 300, 0}
              %{width: 212, height: 104} -> {104, 212, -90}
            end

          %{
            busy_pin: busy_pin,
            reset_pin: reset_pin,
            dc_pin: dc_pin,
            spi: spi,
            eeprom: eeprom,
            rows: rows,
            cols: cols,
            rotation: rot,
            lut: Inky.LUT.table(eeprom),
            border_color: :white,
            pixels: pixels
          }

        true ->
          config
      end

    GPIO.write(config.reset_pin, 0)
    Process.sleep(100)
    GPIO.write(config.reset_pin, 1)
    Process.sleep(100)

    config
    |> send_command(<<0x12>>)

    # |> busy_wait()
  end

  defp busy_wait(%{busy_pin: ref} = config) do
    if GPIO.read(ref) == 0 do
      config
    else
      Process.sleep(100)
      busy_wait(config)
    end
  end

  defp update(config, buf_a, buf_b, busy_wait) do
    setup(config)

    packed_height = <<config.rows::little-16>>
    # Set Analog Block Control
    send_command(config, 0x74, 0x54)
    # Set Digital Block Control
    send_command(config, 0x7E, 0x3B)

    # Gate setting
    send_command(config, 0x01, packed_height <> <<0>>)

    # Gate Driving Voltage
    send_command(config, 0x03, 0x17)
    # Source Driving Voltage
    send_command(config, 0x04, [0x41, 0xAC, 0x32])

    # Dummy line period
    send_command(config, 0x3A, 0x07)
    # Gate line width
    send_command(config, 0x3B, 0x04)
    # Data entry mode setting 0x03 = X/Y increment
    send_command(config, 0x11, 0x03)

    # VCOM Register, 0x3c = -1.5v?
    send_command(config, 0x2C, 0x3C)

    send_command(config, 0x3C, <<0, 0, 0, 0, 0, 0, 0, 0>>)

    case config.border_color do
      # GS Transition Define A + VSS + LUT0
      :black -> send_command(config, 0x3C, <<0, 0, 0, 0, 0, 0, 0, 0>>)
      # Fix Level Define A + VSH2 + LUT3
      :red -> send_command(config, 0x3C, 0b01110011)
      # GS Transition Define A + VSH2 + LUT3
      :yellow -> send_command(config, 0x3C, 0b00110011)
      # GS Transition Define A + VSH2 + LUT1
      :white -> send_command(config, 0x3C, 0b00110001)
    end

    if config.eeprom.color == :yellow do
      # Set voltage of VSH and VSL
      send_command(config, 0x04, <<0x07, 0xAC, 0x32>>)
    end

    if %{eeprom: %{color: :red}, width: 400, height: 300} == config do
      send_command(config, 0x04, <<0x30, 0xAC, 0x22>>)
    end

    # Set LUTs
    send_command(config, 0x32, config.lut)

    # Set RAM X Start/End
    send_command(config, 0x44, <<0x00, div(config.cols, 8) - 1>>)
    # Set RAM Y Start/End
    send_command(config, 0x45, <<0x00, 0x00>> <> packed_height)

    # B/W Update
    # Set RAM X Pointer Start
    send_command(config, 0x4E, 0x00)
    # Set RAM Y Pointer Start
    send_command(config, 0x4F, <<0x00, 0x00>>)
    send_command(config, 0x24, buf_a)

    # Color Update
    # Set RAM X Pointer Start
    send_command(config, 0x4E, 0x00)
    # Set RAM Y Pointer Start
    send_command(config, 0x4F, <<0x00, 0x00>>)
    send_command(config, 0x26, buf_b)

    # Display Update Sequence
    send_command(config, 0x22, 0xC7)
    # Trigger Display Update
    send_command(config, 0x20)
    Process.sleep(50)

    if busy_wait, do: busy_wait(config)

    config
  end

  def set_pixel(config, x, y, color) when color in @valid_colors do
    config
    |> update_in([:pixels], &Matrix.set(&1, x, y, color_value(color)))
  end

  def show(config, busy_wait \\ true) do
    buf_a = pixel_buffer_to_binary(config.pixels, :black)
    buf_b = pixel_buffer_to_binary(config.pixels, :red)
    update(config, buf_a, buf_b, busy_wait)
  end

  def set_border(%{eeprom: %{color: board_color}} = config, border_color)
      when border_color in [:white, :black] or border_color == board_color,
      do: Map.put(config, :border_color, border_color)

  def send_command(config, command, data \\ nil)

  def send_command(config, command, data) when is_integer(command),
    do: send_command(config, <<command>>, data)

  def send_command(config, command, data)

  def send_command(%{spi: spi, dc_pin: dc_pin} = config, command, data) do
    :ok = GPIO.write(dc_pin, 0)
    spi_transfer(spi, command)
    send_data(config, data)
  end

  def send_data(config, data) when data in [nil, []], do: config
  def send_data(config, data) when is_integer(data), do: send_data(config, <<data>>)
  def send_data(config, data) when is_list(data), do: send_data(config, List.to_string(data))

  def send_data(%{dc_pin: dc_pin, spi: spi} = config, data) when is_binary(data) do
    :ok = GPIO.write(dc_pin, 1)
    spi_transfer(spi, data)
    config
  end

  def spi_transfer(spi, <<chunk::binary-size(4096), rest::binary>> = data)
      when bit_size(rest) > 0 do
    spi_transfer(spi, chunk)
    spi_transfer(spi, rest)
  end

  def spi_transfer(spi, data) do
    case SPI.transfer(spi, data) do
      {:ok, _any} ->
        :ok

      {:error, err} ->
        raise "#{inspect(err)} with len #{bit_size(data)} data #{
                inspect(data, printable_limit: :infinity)
              }"
    end
  end

  def color_value(:white), do: 0
  def color_value(:black), do: 1
  def color_value(:red), do: 2
  def color_value(:yellow), do: 2

  def pixel_buffer_to_binary(pixels, color) do
    buf =
      pixels
      |> List.flatten()
      |> Enum.map(fn i ->
        cond do
          color == :black && i == 1.0 -> 0
          color == :black -> 1
          color == :red && i == 2.0 -> 1
          color == :yellow && i == 2.0 -> 1
          true -> 0
        end
      end)

    resp = for i <- buf, do: <<i::size(1)>>
    pad(resp)
  end

  def pad(binary) do
    rem(Enum.count(binary), 8)
    |> case do
      0 ->
        binary

      num ->
        pad = 8 - num
        binary ++ [<<0::size(pad)>>]
    end
    |> Enum.into(<<>>)
  end
end
