defmodule ExCompilationCache do
  @moduledoc """
  Compilation cache is responsible for:
    1. Creating and uploading a build cache of the current compilation if it includes a specific "upstream" commit;
    2. Detecting if the current code "snapshot" includes a given "upstream" commit;
    3. Checking if there's already a compilation cache that can be useful for the current local branch in the configured cache backend;
    4. Download a cached build for the current code "snapshot" from the configured cache.
  """

  require Logger

  alias ExCompilationCache.BuildCache
  alias ExCompilationCache.Git
  alias ExCompilationCache.Zip

  @doc """
  Creates the build cache and uploads it. It assumes the compilation already succeeded, so it will
  use the existing compilation artifacts stored in  `_build/<mix_env>`.

  Use it like this:

  ```
  ExCompilationCache.create_and_upload_build_cache(:dev, "origin/main", "12345", ExCompilationCache.S3Backend)
  ```
  """
  def create_and_upload_build_cache(mix_env, remote_branch, zip_password, cache_backend) do
    with {:ok, build_directory} <- check_build_directory(mix_env),
      {:ok, {commit_hash, _branches}} <- Git.latest_commit_also_present_in_remote(remote_branch),
      artifact = BuildCache.new(mix_env, commit_hash),
      {:ok, local_artifact_path} <- Zip.zip_directory(build_directory, "_build/#{BuildCache.artifact_name(artifact)}", zip_password),
      :ok <- cache_backend.setup_before_upload() do
      remote_artifact_path = BuildCache.remote_artifact_path(artifact, :zip)

      cache_backend.upload_cache_artifact(local_artifact_path, remote_artifact_path)
    end
  end

  @doc """
  This function checks if the current local branch includes an "upstream" commit.

  If so, it means that a compilation cache built for the current code will be useful (as in, can be used as cache),
  for other users who also have checked out a branch that includes the "upstream" commit.

  From another perspective, it also means that if a compilation cache exists, it will be useful for the current user.

  Use it like this:

  ```
  ExCompilationCache.current_code_includes_upstream_commit?("origin/main")
  ```
 """
  def current_code_includes_upstream_commit?(remote_branch) do
    case Git.latest_commit_also_present_in_remote(remote_branch) do
      {:ok, {_commit_hash, _branches}} ->
        true
      _ ->
        false
    end
  end

  @doc """
  This function checks if there is a compilation cache for an "upstream" commit that also belongs to the current local branch.

  Use it like this:

  ```
  ExCompilationCache.cached_build?(:dev, "origin/main", ExCompilationCache.S3Backend)
  ```
  """
  def cached_build?(mix_env, remote_branch, cache_backend) do
    with true <- current_code_includes_upstream_commit?(remote_branch),
      {:ok, {commit_hash, _branches}} <- Git.latest_commit_also_present_in_remote(remote_branch),
      local_artifact = BuildCache.new(mix_env, commit_hash),
      {:ok, _remote_artifact} <- cache_backend.fetch_cache_artifact(local_artifact) do
      true
    else
      {:error, _} ->
        false
    end
  end

  def download_and_apply_cached_build do
    :TODO
  end

  defp check_build_directory(mix_env) do
    build_directory = "_build/#{mix_env}"

    case File.stat(build_directory) do
      {:ok, %File.Stat{type: :directory}} ->
        {:ok, build_directory}

      error ->
        Logger.error("[ExCompilationCache] Problem with build directory: #{inspect(error)}")

        error
    end
  end

end
