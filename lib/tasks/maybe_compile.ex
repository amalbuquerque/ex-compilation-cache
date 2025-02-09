defmodule Mix.Tasks.Maybe.Compile do
  use Mix.Task

  def run(_) do
    mix_env = :dev
    remote_branch = "origin/master"
    zip_password = "12345"
    cache_backend = ExCompilationCache.S3Backend

    previous_log_level = Logger.level()

    Logger.configure(level: :info)

    ExCompilationCache.download_cache_or_compile_and_upload(
      mix_env,
      remote_branch,
      zip_password,
      cache_backend
    )

    Logger.configure(level: previous_log_level)
  end
end
