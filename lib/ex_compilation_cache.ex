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
  Should be called when a compilation needs to be done.

  It will always try to download a cached artifact for the latest `master` commit if available,
  otherwise it will compile and then cache the resulting compilation.
  """
  def download_cache_or_compile_and_upload(mix_env, remote_branch, zip_password, cache_backend) do
    if cached_build?(mix_env, remote_branch, cache_backend) do
      IO.puts("👷🚛 Downloading the build cache...")

      download_and_apply_cached_build(mix_env, remote_branch, zip_password, cache_backend)

      IO.puts("✅ Build cache downloaded and put in place 🌈")
      :ok
    else
      IO.puts("👷🏗️ Will compile the code and upload a new build cache...")

      case Mix.Task.run("compile") do
        {ok_or_noop, _} when ok_or_noop in [:ok, :noop] ->
          create_and_upload_build_cache(mix_env, remote_branch, zip_password, cache_backend)

          IO.puts("✅ Build cache uploaded. Thank you for taking the time!")
          :ok

        compilation_result ->
          # compilation failed, let's end here
          IO.puts("Nothing to do. (compilation result=#{inspect(compilation_result)})")

          :noop
      end
    end
  end

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
         {:ok, {commit_hash, _branches}} <-
           Git.latest_commit_also_present_in_remote(remote_branch),
         artifact = BuildCache.new(mix_env, commit_hash),
         {:ok, local_artifact_path} <-
           Zip.zip_directory(
             build_directory,
             "_build/#{BuildCache.artifact_name(artifact)}",
             zip_password
           ),
         :ok <- cache_backend.setup_before() do
      remote_artifact_path = BuildCache.remote_artifact_path(artifact, :zip)

      result = cache_backend.upload_cache_artifact(local_artifact_path, remote_artifact_path)

      delete_file(local_artifact_path)

      result
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
         {:ok, {commit_hash, _branches}} <-
           Git.latest_commit_also_present_in_remote(remote_branch),
         local_artifact = BuildCache.new(mix_env, commit_hash),
         :ok <- cache_backend.setup_before(),
         {:ok, _remote_artifact} <- cache_backend.fetch_cache_artifact(local_artifact) do
      IO.puts(
        "🍏 There is a build cache for commit='#{commit_hash}' and '#{local_artifact.architecture}'"
      )

      true
    else
      {:error, reason} ->
        IO.puts("🙅 No build cache available (reason=#{inspect(reason)})")
        false
    end
  end

  @doc """
  Use it like this:

  ```
  ExCompilationCache.download_and_apply_cached_build(:dev, "origin/main", "12345", ExCompilationCache.S3Backend)
  ```
  """
  def download_and_apply_cached_build(mix_env, remote_branch, zip_password, cache_backend) do
    with true <- current_code_includes_upstream_commit?(remote_branch),
         {:ok, {commit_hash, _branches}} <-
           Git.latest_commit_also_present_in_remote(remote_branch),
         local_artifact = BuildCache.new(mix_env, commit_hash),
         :ok <- cache_backend.setup_before(),
         {:ok, remote_artifact} <- cache_backend.fetch_cache_artifact(local_artifact),
         remote_artifact_path = BuildCache.remote_artifact_path(remote_artifact, :zip),
         :ok = File.mkdir_p("_build"),
         artifact_name = BuildCache.artifact_name(remote_artifact, :zip),
         local_artifact_path = Path.join("_build", artifact_name),
         {:ok, _} <-
           cache_backend.download_cache_artifact(remote_artifact_path, local_artifact_path) do
      # unzip to . since zip has _build/<mix_env> folder structure
      result = Zip.unzip_to(local_artifact_path, ".", zip_password)

      delete_file(local_artifact_path)

      result
    end
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

  defp delete_file(file_path) do
    System.cmd("rm", ~w[-rf #{file_path}])
  end
end
