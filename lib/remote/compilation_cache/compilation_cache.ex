defmodule Remote.CompilationCache do
  @moduledoc """
  Compilation cache is responsible for:
    1. Creating a build cache of the current compilation if it matches a specific "upstream" commit;
    2. Detecting if the current code "snapshot" matches a given "upstream" commit;
    3. Checking if there's already a cached build for the current code "snapshot" in the configured cache;
    4. Download a cached build for the current code "snapshot" from the configured cache.
  """

  def create_build_cache do
    :TODO
  end

  def current_code_matches_upstream_commit? do
    :TODO
  end

  def cached_build? do
    :TODO
  end

  def download_and_apply_cached_build do
    :TODO
  end
end
