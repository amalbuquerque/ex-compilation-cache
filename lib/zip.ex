defmodule ExCompilationCache.Zip do
  @moduledoc """
  This module provides functionality to zip and unzip a folder with password.
  """

  require Logger

  # note that we don't try to compress any file to speed up compress/decompress time, see the `-0` flag
  @zip_args ~w[<archive_file_path> -r <folder_path> --quiet -0]
  @unzip_args ~w[-qq -o <archive_file_path> -d <target_path>]

  @doc """
  Use it like this:

  ```
  ExCompilationCache.Zip.zip_directory("foo/bar", "foo_bar.zip")
  ExCompilationCache.Zip.zip_directory("_build/dev", "dev_cache.zip", "12345")
  ```
  """
  def zip_directory(folder_path, archive_file_path, password \\ nil) do
    archive_file_path = maybe_add_zip_extension(archive_file_path)

    args =
      Enum.map(@zip_args, fn
        "<archive_file_path>" ->
          archive_file_path

        "<folder_path>" ->
          folder_path

        arg ->
          arg
      end)

    args = maybe_set_zip_password(args, password)

    ensure_file_exists!(folder_path, "Folder to zip")

    case System.cmd("zip", args) do
      {output, 0} ->
        Logger.debug("[Zip] Successful zip! Output: #{inspect(output)}")

        {:ok, archive_file_path}

      error_result ->
        {:error, error_result}
    end
  end

  defp maybe_set_zip_password(args, _password = nil), do: args
  defp maybe_set_zip_password(args, password), do: args ++ ["--password", password]

  @doc """
  Use it like this:

  ```
  ExCompilationCache.Zip.unzip_to("dev_cache.zip", "temp/foo")
  ExCompilationCache.Zip.unzip_to("dev_cache.zip", ".", "12345")
  ```
  """
  def unzip_to(archive_file_path, target_path, password \\ nil) do
    args =
      Enum.map(@unzip_args, fn
        "<archive_file_path>" ->
          maybe_add_zip_extension(archive_file_path)

        "<target_path>" ->
          target_path

        arg ->
          arg
      end)

    args = maybe_set_unzip_password(args, password)

    ensure_file_exists!(archive_file_path, "Archive to unzip")
    ensure_file_exists!(target_path, "Target folder")

    case System.cmd("unzip", args) do
      {_output, 0} ->
        :ok

      {_output, error_exit_status} ->
        {:error, {:command_failed, error_exit_status}}
    end
  end

  defp maybe_set_unzip_password(args, _password = nil), do: args
  defp maybe_set_unzip_password(args, password), do: ["-P", password] ++ args

  defp ensure_file_exists!(file_path, description) do
    unless File.exists?(file_path) do
      raise "#{description} ('#{file_path}') doesn't exist... Current directory: #{File.cwd!()}"
    end
  end

  defp maybe_add_zip_extension(file_path) do
    if String.ends_with?(file_path, ".zip") do
      file_path
    else
      "#{file_path}.zip"
    end
  end
end
