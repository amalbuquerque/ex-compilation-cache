defmodule ExCompilationCache.BuildCacheTest do
  use ExUnit.Case, async: true

  use Mimic

  alias ExCompilationCache.BuildCache

  setup do
    Mimic.copy(File)

    :ok
  end

  @mix_env :dev
  @commit_hash "1234567890abcdef1234567890abcdef"
  @now ~U[2024-11-16 23:50:10.881572Z]

  describe "new/2" do
    test "returns the expected Linux struct" do
      expect_linux()

      assert linux_build_cache = BuildCache.new(@mix_env, @commit_hash)

      assert linux_build_cache.architecture == :x86_64
      assert linux_build_cache.operating_system == :linux
      assert linux_build_cache.mix_env == @mix_env
      assert linux_build_cache.commit_hash == @commit_hash
      assert is_struct(linux_build_cache.timestamp, DateTime)
    end

    test "returns the expected MacOS struct" do
      expect_macos()

      assert macos_build_cache = BuildCache.new(@mix_env, @commit_hash)

      assert macos_build_cache.architecture == :aarm64
      assert macos_build_cache.operating_system == :macos
      assert macos_build_cache.mix_env == @mix_env
      assert macos_build_cache.commit_hash == @commit_hash
      assert is_struct(macos_build_cache.timestamp, DateTime)
    end
  end

  describe "new/5" do
    test "returns the expected struct" do
      assert build_cache =
               BuildCache.new(:aarm64, :macos, @mix_env, @commit_hash, DateTime.utc_now())

      assert build_cache.architecture == :aarm64
      assert build_cache.operating_system == :macos
      assert build_cache.mix_env == @mix_env
      assert build_cache.commit_hash == @commit_hash
      assert is_struct(build_cache.timestamp, DateTime)
    end

    test "it checks the architecture, OS and mix env" do
      assert_raise FunctionClauseError, fn ->
        BuildCache.new(:invalid_arch, :macos, @mix_env, @commit_hash, DateTime.utc_now())
      end

      assert_raise FunctionClauseError, fn ->
        BuildCache.new(:aarm64, :invalid_os, @mix_env, @commit_hash, DateTime.utc_now())
      end

      assert_raise FunctionClauseError, fn ->
        BuildCache.new(:aarm64, :macos, :invalid_mix_env, @commit_hash, DateTime.utc_now())
      end
    end
  end

  describe "parse/2" do
    test "parses an artifact name to a BuildCache struct again" do
      artifact_name_with_extension = "aarm64_macos_#{@mix_env}_#{@commit_hash}_20241116235010.zip"

      assert build_cache = BuildCache.parse(artifact_name_with_extension)

      assert build_cache.architecture == :aarm64
      assert build_cache.operating_system == :macos
      assert build_cache.mix_env == @mix_env
      assert build_cache.commit_hash == @commit_hash
      assert is_struct(build_cache.timestamp, DateTime)
    end
  end

  describe "artifact_name/2" do
    test "returns the artifact name for a BuildCache" do
      assert build_cache = BuildCache.new(:aarm64, :macos, @mix_env, @commit_hash, @now)

      assert artifact_name = BuildCache.artifact_name(build_cache)
      assert artifact_name_with_extension = BuildCache.artifact_name(build_cache, "zip")

      assert "aarm64_macos_#{@mix_env}_#{@commit_hash}_20241116235010" == artifact_name

      assert "aarm64_macos_#{@mix_env}_#{@commit_hash}_20241116235010.zip" ==
               artifact_name_with_extension
    end
  end

  describe "remote_artifact_path/2" do
    test "returns the expected remote full path" do
      assert build_cache = BuildCache.new(:aarm64, :macos, @mix_env, @commit_hash, @now)

      remote_full_path = BuildCache.remote_artifact_path(build_cache, "zip")

      assert remote_full_path ==
               "aarm64/#{@mix_env}/aarm64_macos_dev_1234567890abcdef1234567890abcdef_20241116235010.zip"
    end
  end

  describe "search_prefix" do
    test "returns the expected search prefix" do
      assert build_cache = BuildCache.new(:aarm64, :macos, @mix_env, @commit_hash, @now)

      search_prefix = BuildCache.search_prefix(build_cache)

      # doesn't include the commit hash suffix
      assert search_prefix == "aarm64/dev/aarm64_macos_dev_1234567890abcdef1234567890abcdef"
    end
  end

  # expect 2 times because File.exists?/1 is called twice, once for architecture, the other for OS
  def expect_linux, do: expect(File, :exists?, 2, fn "/proc/cpuinfo" -> true end)
  def expect_macos, do: expect(File, :exists?, 2, fn "/proc/cpuinfo" -> false end)
end
