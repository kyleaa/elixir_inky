defmodule ElixirInky.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_inky,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:circuits_gpio, "~> 0.1"},
      {:circuits_spi, "~> 0.1"},
      {:circuits_i2c, "~> 0.1"},
      {:matrix, "~> 0.3"}
    ]
  end
end
