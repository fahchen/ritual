defmodule RitualTest do
  use ExUnit.Case
  doctest Ritual

  test "greets the world" do
    assert Ritual.hello() == :world
  end
end
