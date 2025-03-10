defmodule ExCompilationCache.Behaviours.CacheBackend do
  @moduledoc """
  Behaviour that a specific cache backend (e.g. S3) should implement
  to be used as a compilation cache.
  """

  alias ExCompilationCache.BuildCache

  @doc """
  Function that will be called before trying to upload or download a compilation artifact.

  Use it for any kind of setup (e.g. authentication) required for the operation to be successful.
  """
  @callback setup_before() :: :ok

  @doc """
  Function that will be called to upload a compilation artifact.

  It receives the local path of the compilation artifact ready to be uploaded, and the full path
  where the artifact should be uploaded to.

  We need to distinguish those because the artifact in the filesystem might live in a temporary folder
  (e.g. `/tmp/foo.zip`), whereas the artifact should be stored remotely in
  `<architecture>/<operation_system>_<mix_env>_<commit_hash>_<timestamp>.zip`.

  It should return an :ok tuple or an :error tuple, depending on the upload outcome:
  """
  @callback upload_cache_artifact(local_path :: String.t(), artifact_remote_path :: String.t()) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Function that will be called to download a compilation cache artifact.

  It receives the full remote path of the artifact and it should download the artifact to the local filesystem.

  It should return an :ok tuple with the full path of the downloaded compilation artifact, or an :error tuple.
  """
  @callback download_cache_artifact(
              artifact_remote_path :: String.t(),
              artifact_local_path :: String.t()
            ) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Function that returns a cache artifact if it exists in the remote storage.
  """
  @callback fetch_cache_artifact(local_artifact :: BuildCache.t()) ::
              {:ok, BuildCache.t()} | {:error, :remote_cache_artifact_not_found}

  @doc """
  Function that returns all cache artifacts that are remotely available.

  Receives the current `mix_env` to filter the available cache artifacts by it, along with the current architecture.
  """
  @callback list_cache_artifacts(mix_env :: atom()) :: {:ok, [BuildCache.t()]} | {:error, term()}
end
