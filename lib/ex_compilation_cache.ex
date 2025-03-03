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

  If `force` is true, it will force the local compilation and upload, even if there is a cached build that can be used.
  """
  def download_cache_or_compile_and_upload(
        mix_env,
        remote_branch,
        zip_password,
        cache_backend,
        force
      ) do
    cached_build_result = cached_build(mix_env, remote_branch, cache_backend)
    cached_build? = match?({:ok, _}, cached_build_result)

    if force or not cached_build? do
      IO.puts("👷🏗️ Will compile the code and upload a new build cache... (force=#{force})")

      compile_and_upload(mix_env, remote_branch, zip_password, cache_backend)
    else
      IO.puts("👷🚛 Downloading the build cache...")

      {:ok, remote_artifact} = cached_build_result

      %{
        fetch_elapsed_time_ms: fetch_time_ms,
        download_elapsed_time_ms: download_time_ms,
        unzip_elapsed_time_ms: unzip_time_ms
      } =
        download_and_apply_cached_build(
          mix_env,
          remote_branch,
          zip_password,
          cache_backend,
          remote_artifact
        )

      IO.puts(
        "✅ Build cache downloaded and put in place (took #{fetch_time_ms / 1000} secs for finding build cache, took #{download_time_ms / 1000} secs for download, #{unzip_time_ms / 1000} secs for unzip) 🌈"
      )

      IO.puts("👷🏗️ Will now compile the diff between local code and build cache...")

      compile()

      IO.puts("👷🏗️ Creating a new cache to upload 🚀")

      create_and_upload_build_cache(mix_env, remote_branch, zip_password, cache_backend)

      :ok
    end
  end

  defp compile do
    # Task.run/1 will only run once, following executions will return :noop, hence the usage of rerun/1 to *always* execute the given task
    {elapsed_msg, result} = timed_exec(fn -> Mix.Task.rerun("compile") end)

    case result do
      {:ok, _} ->
        IO.puts("🏁 Compilation finished #{elapsed_msg}")

        :ok

      {:noop, _} ->
        IO.puts("Nothing to compile 😎 #{elapsed_msg}")

        :noop

      compilation_result ->
        IO.puts(
          "Compilation failed #{elapsed_msg}! Compilation result:\n#{inspect(compilation_result)}"
        )

        compilation_result
    end
  end

  defp compile_and_upload(mix_env, remote_branch, zip_password, cache_backend) do
    if compile() in [:ok, :noop] do
      {timed_elapsed_msg, result} =
        timed_exec(fn ->
          create_and_upload_build_cache(mix_env, remote_branch, zip_password, cache_backend)
        end)

      IO.puts(
        "✅ Build cache zipped and uploaded #{timed_elapsed_msg}. Thank you for taking the time!"
      )

      result
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
  This function checks if there is a compilation cache for an "upstream" commit that also belongs to the current local
  branch and returns the `BuildCache` struct representing the build cache.

  Example:

  Upstream branch has: commits `C4(HEAD)<-C3<-C2<-C1<-(...)`
  Local branch has: `X3(HEAD)<-X2<-X1<-C4<-C3*<-C2*<-C1<-(...)`

  No one uploaded a cached build for `C4` yet. Only `C3` and `C2` commits have a build cache (both have an `*`).

  In this example, `cached_build/3` will return an `{:ok, %BuildCache{}}` since it finds `C3` in the local branch as
  the latest commit that is also present in the upstream for which there is a build cache.

  Use it like this:

  ```
  ExCompilationCache.cached_build(:dev, "origin/main", ExCompilationCache.S3Backend)
  ```
  """
  def cached_build(mix_env, remote_branch, cache_backend) do
    with true <- current_code_includes_upstream_commit?(remote_branch),
         {:ok, {commit_hash, _branches}} <-
           Git.latest_commit_also_present_in_remote(remote_branch),
         Logger.debug("Latest local commit present in remote branch: #{commit_hash}"),
         {:ok, remote_artifact} <-
           latest_available_build_cache(commit_hash, mix_env, cache_backend) do
      IO.puts(
        "🍏 There is a build cache for commit='#{commit_hash}' and '#{remote_artifact.architecture}', #{remote_artifact}"
      )

      {:ok, remote_artifact}
    else
      {:error, reason} ->
        IO.puts("🙅 No build cache available (reason=#{inspect(reason)})")
        {:error, :build_cache_not_found}
    end
  end

  # starts from the latest_commit, and tries to find the latest cache available
  defp latest_available_build_cache(latest_commit, mix_env, cache_backend) do
    commits_to_check = Git.commit_list(latest_commit)

    with :ok <- cache_backend.setup_before() do
      Enum.reduce_while(commits_to_check, nil, fn commit_hash, acc ->
        temp_artifact = BuildCache.new(mix_env, commit_hash)

        Logger.debug("Checking if '#{commit_hash}' has a cached build...")

        case cache_backend.fetch_cache_artifact(temp_artifact) do
          {:ok, remote_artifact} ->
            Logger.debug("Found a cached build for: #{remote_artifact} 🌈")

            {:halt, {:ok, remote_artifact}}

          _ ->
            {:cont, acc}
        end
      end)
    end
  end

  @doc """
  Function responsible to find the latest cached build, download it and unzip it to the right place.

  If a `remote_artifact` is passed in as parameter, it skips the "find the latest cached build" step.

  Use it like this:

  ```
  ExCompilationCache.download_and_apply_cached_build(:dev, "origin/main", "12345", ExCompilationCache.S3Backend)
  ExCompilationCache.download_and_apply_cached_build(:dev, "origin/main", "12345", ExCompilationCache.S3Backend, remote_artifact)
  ```
  """
  def download_and_apply_cached_build(
        mix_env,
        remote_branch,
        zip_password,
        cache_backend,
        remote_artifact \\ nil
      ) do
    cached_build_fn = fn remote_artifact ->
      if remote_artifact do
        {:ok, remote_artifact}
      else
        cached_build(mix_env, remote_branch, cache_backend)
      end
    end

    with before_fetch_artifact = now_milliseconds(),
         {:ok, remote_artifact} <- cached_build_fn.(remote_artifact),
         remote_artifact_path = BuildCache.remote_artifact_path(remote_artifact, :zip),
         :ok = File.mkdir_p("_build"),
         artifact_name = BuildCache.artifact_name(remote_artifact, :zip),
         local_artifact_path = Path.join("_build", artifact_name),
         before_download_artifact = now_milliseconds(),
         {:ok, _} <-
           cache_backend.download_cache_artifact(remote_artifact_path, local_artifact_path) do
      download_elapsed_time_ms = now_milliseconds() - before_download_artifact
      fetch_elapsed_time_ms = before_download_artifact - before_fetch_artifact

      # unzip to . since zip has _build/<mix_env> folder structure
      {unzip_elapsed_time_ms, result} =
        :timer.tc(
          fn ->
            unzip_result = Zip.unzip_to(local_artifact_path, ".", zip_password)
            delete_file(local_artifact_path)

            unzip_result
          end,
          :millisecond
        )

      %{
        fetch_elapsed_time_ms: fetch_elapsed_time_ms,
        download_elapsed_time_ms: download_elapsed_time_ms,
        unzip_elapsed_time_ms: unzip_elapsed_time_ms,
        result: result
      }
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

  defp timed_exec(fun_to_exec) do
    {elapsed_time_ms, result} = :timer.tc(fun_to_exec, :millisecond)

    elapsed_msg = "(took #{elapsed_time_ms / 1000} seconds)"

    {elapsed_msg, result}
  end

  defp now_milliseconds, do: :erlang.monotonic_time(:millisecond)
end
