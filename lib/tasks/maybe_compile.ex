defmodule Mix.Tasks.Maybe.Compile do
  use Mix.Task

  def run(args) do
    options = parse_args(args)

    previous_log_level = Logger.level()

    Logger.configure(level: options.log_level)

    ExCompilationCache.download_cache_or_compile_and_upload(
      options.mix_env,
      options.remote_branch,
      options.zip_password,
      options.cache_backend
    )

    Logger.configure(level: previous_log_level)
  end

  defp parse_args(args) do
    parse_config = [
      strict: [
        mix_env: :string,
        remote_branch: :string,
        zip_password: :string,
        cache_backend: :string,
        log_level: :string
      ],
      aliases: [
        m: :mix_env,
        r: :remote_branch,
        z: :zip_password,
        b: :cache_backend,
        l: :log_level
      ]
    ]

    {parsed_args, _, _} = OptionParser.parse(args, parse_config)

    %{
      mix_env: mix_env!(parsed_args),
      remote_branch: remote_branch!(parsed_args),
      zip_password: parsed_args[:zip_password],
      cache_backend: cache_backend!(parsed_args),
      log_level: log_level!(parsed_args)
    }
  end

  defp mix_env!(parsed_args) do
    mix_env =
      parsed_args
      |> Keyword.get(:mix_env, "dev")
      |> String.to_atom()

    if mix_env not in [:dev, :test] do
      raise "`mix_env` can only be dev or test"
    else
      mix_env
    end
  end

  defp remote_branch!(parsed_args) do
    remote_branch = parsed_args[:remote_branch]

    if is_nil(remote_branch) do
      raise "`remote_branch` need to be set"
    else
      remote_branch
    end
  end

  defp cache_backend!(parsed_args) do
    cache_backend = parsed_args[:cache_backend]

    if is_nil(cache_backend) do
      raise "`cache_backend` need to be set"
    end

    "Elixir"
    |> Module.concat(cache_backend)
    |> Code.ensure_compiled()
    |> case do
      {:module, module} ->
        module

      error ->
        raise "`cache_backend` module not found (error='#{inspect(error)}')"
    end
  end

  defp log_level!(parsed_args) do
    parsed_args
    |> Keyword.get(:log_level, "info")
    |> String.to_existing_atom()
  end
end
