defmodule CompilationCacheTest do
  use ExUnit.Case
  doctest CompilationCache

  test "greets the world" do
    assert CompilationCache.hello() == :world
  end
end
