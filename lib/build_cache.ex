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

  def new(mix_env, commit_hash) do
    architecture = current_architecture()
    operating_system = current_operating_system()

    new(architecture, operating_system, mix_env, commit_hash)
  end

  def new(architecture, operating_system, mix_env, commit_hash)
      when architecture in @cacheable_architectures and
             operating_system in @cacheable_operating_systems and
             mix_env in @cacheable_mix_envs do
    %__MODULE__{
      architecture: architecture,
      operating_system: operating_system,
      mix_env: mix_env,
      commit_hash: commit_hash,
      timestamp: DateTime.utc_now()
    }
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
