defmodule ExCompilationCache.Behaviours.CacheBackend do
  @moduledoc """
  Behaviour that a specific cache backend (e.g. S3) should implement
  to be used as a compilation cache.
  """

  @doc """
  Function that will be called before trying to upload a compilation artifact.

  Use it for any kind of setup (e.g. authentication) required for the upload to be successful.
  """
  @callback setup_before_upload() :: :ok

  @doc """
  Function that will be called to upload a compilation artifact.

  It receives the local path of the compilation artifact ready to be uploaded, and the full path
  where the artifact should be uploaded to.

  We need to distinguish those because the artifact in the filesystem might live in a temporary folder
  (e.g. `/tmp/foo.zip`), whereas the artifact should be stored remotely in
  `<architecture>/<operation_system>_<mix_env>_<commit_hash>_<timestamp>.zip`.

  It should return an :ok tuple or an :error tuple, depending on the upload outcome:
  """
  @callback upload_cache_artifact(local_path :: String.t(), artifact_remote_path :: String.t()) :: {:ok, term()} | {:error, term()}

  @doc """
  Function that will be called to download a compilation artifact.

  It receives the full remote path of the artifact and it should download the artifact to the local filesystem.

  It should return an :ok tuple with the full path of the downloaded compilation artifact, or an :error tuple.
  """
  @callback download_cache_artifact(artifact_remote_path :: String.t(), artifact_local_path :: String.t()) :: {:ok, String.t()} | {:error, term()}
end
