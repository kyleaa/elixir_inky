defmodule ElixirInkyTest do
  use ExUnit.Case
  doctest ElixirInky

  test "greets the world" do
    assert ElixirInky.hello() == :world
  end
end
