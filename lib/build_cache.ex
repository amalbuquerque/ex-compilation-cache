defmodule ExCompilationCache.BuildCache do
  @moduledoc """
  Struct representing a build cache.
  """

  use TypedStruct

  typedstruct do
    field(:architecture, atom())
    field(:operating_system, atom())
    field(:mix_env, atom())
    field(:commit_hash, String.t())
    field(:timestamp, DateTime.t())
  end

  @cacheable_architectures [:aarm64, :x86_64]
  @cacheable_operating_systems [:macos, :linux]
  @cacheable_mix_envs [:dev, :test]

  @doc """
  Returns a struct with: architecture, operating_system, mix_env, commit_hash, timestamp.
  """
  def new(mix_env, commit_hash) do
    architecture = current_architecture()
    operating_system = current_operating_system()

    new(architecture, operating_system, mix_env, commit_hash)
  end

  def new(architecture, operating_system, mix_env, commit_hash, timestamp \\ DateTime.utc_now())
      when architecture in @cacheable_architectures and
             operating_system in @cacheable_operating_systems and
             mix_env in @cacheable_mix_envs do
    %__MODULE__{
      architecture: architecture,
      operating_system: operating_system,
      mix_env: mix_env,
      commit_hash: commit_hash,
      timestamp: timestamp
    }
  end

  def parse(artifact_name) do
    # drop the extension
    artifact_name = String.trim_trailing(artifact_name, Path.extname(artifact_name))

    architecture =
      Enum.find(@cacheable_architectures, &String.contains?(artifact_name, to_string(&1)))

    operating_system =
      Enum.find(@cacheable_operating_systems, &String.contains?(artifact_name, to_string(&1)))

    mix_env = Enum.find(@cacheable_mix_envs, &String.contains?(artifact_name, to_string(&1)))

    [timestamp_string, commit_hash | _] =
      artifact_name
      |> String.split("_")
      |> Enum.reverse()

    timestamp = parse_timestamp(timestamp_string)

    new(architecture, operating_system, mix_env, commit_hash, timestamp)
  end

  defp parse_timestamp(
         <<yyyy::binary-4, month::binary-2, dd::binary-2, hh::binary-2, minutes::binary-2,
           seconds::binary-2>>
       ) do
    {:ok, timestamp, 0} =
      DateTime.from_iso8601("#{yyyy}-#{month}-#{dd} #{hh}:#{minutes}:#{seconds}Z")

    timestamp
  end

  def artifact_name(%__MODULE__{} = artifact, extension \\ nil) do
    parts = [
      artifact.architecture,
      artifact.operating_system,
      artifact.mix_env,
      artifact.commit_hash,
      Calendar.strftime(artifact.timestamp, "%Y%m%d%H%M%S")
    ]

    artifact_name = Enum.join(parts, "_")

    if extension do
      "#{artifact_name}.#{extension}"
    else
      artifact_name
    end
  end

  def remote_artifact_path(%__MODULE__{} = artifact, extension) do
    Enum.join(
      [
        artifact.architecture,
        artifact.mix_env,
        artifact_name(artifact, extension)
      ],
      "/"
    )
  end

  def search_prefix(%__MODULE__{} = artifact) do
    parts = [
      artifact.architecture,
      artifact.operating_system,
      artifact.mix_env,
      artifact.commit_hash
    ]

    search_prefix = Enum.join(parts, "_")

    Enum.join(
      [
        artifact.architecture,
        artifact.mix_env,
        search_prefix
      ],
      "/"
    )
  end

  # to simplify, we assume that only Linux laptops use x86_64, since
  # we're replacing all Intel Macs by new Macs with Apple silicon
  defp current_architecture do
    case current_operating_system() do
      :linux ->
        :x86_64

      :macos ->
        :aarm64
    end
  end

  # `/proc/cpuinfo` only exists on Linux; on MacOS you need to use `sysctl -a | grep cpu`
  defp current_operating_system do
    if File.exists?("/proc/cpuinfo") do
      :linux
    else
      :macos
    end
  end
end
