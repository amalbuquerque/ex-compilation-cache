defmodule ExCompilationCacheTest do
  use ExUnit.Case
  doctest ExCompilationCache

  test "create_build_cache" do
    assert ExCompilationCache.create_build_cache() == :TODO
  end

  test "current_code_matches_upstream_commit?" do
    assert ExCompilationCache.current_code_matches_upstream_commit?() == :TODO
  end

  test "cached_build?" do
    assert ExCompilationCache.cached_build?() == :TODO
  end

  test "download_and_apply_cached_build" do
    assert ExCompilationCache.download_and_apply_cached_build() == :TODO
  end
end
