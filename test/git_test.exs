defmodule ExCompilationCache.GitTest do
  use ExUnit.Case, async: true

  use Mimic

  alias ExCompilationCache.Git

  setup do
    Mimic.copy(System)

    :ok
  end

  describe "current_changes/0" do
    test "it returns the existing changes identified by Git" do
      expect(System, :cmd, fn "git",
                              [
                                "ls-files",
                                "--others",
                                "--modified",
                                "--deleted",
                                "--exclude-standard",
                                "-t"
                              ] ->
        output = File.read!("test/support/git_ls_files_example")

        {output, 0}
      end)

      assert file_list = Git.current_changes()

      grouped_by_mode = Enum.group_by(file_list, fn {mode, _file_path} -> mode end)

      assert grouped_by_mode |> Map.keys() |> Enum.sort() == ["?", "C"]
      assert length(grouped_by_mode["?"]) == 5
      assert length(grouped_by_mode["C"]) == 2
    end

    test "it doesn't fail with no changes" do
      expect(System, :cmd, fn "git",
                              [
                                "ls-files",
                                "--others",
                                "--modified",
                                "--deleted",
                                "--exclude-standard",
                                "-t"
                              ] ->
        # no output from git
        {"", 0}
      end)

      assert [] == Git.current_changes()
    end
  end

  describe "latest_commit_also_present_in_remote/2" do
    test "it returns the local commit also present in the remote branch" do
      # the HEAD~3 commit is contained in the following branches
      list_of_branches_with_commit = """
      remotes/origin/main
      local-branch
      """

      expect_git_rev_list_count()

      0..3
      |> Enum.map(&"HEAD~#{&1}")
      |> expect_branches(list_of_branches_with_commit)

      # the last commit, HEAD~3, will be present in the remotes/origin/main branch
      # so its commit hash will be fetched via Git.commit_hash/1
      expect(System, :cmd, fn "git",
                              ["show", "HEAD~3", "--pretty=oneline", "--no-abbrev-commit"] ->
        output = File.read!("test/support/git_show_example")

        {output, 0}
      end)

      # checking the origin/main and 4 commits
      assert {:ok,
              {"123commit_hash_dummy____git_show_example",
               ["remotes/origin/main", "local-branch"]}} ==
               Git.latest_commit_also_present_in_remote("origin/main", 4)
    end

    test "it only checks the number of commits passed" do
      expect_git_rev_list_count()

      # the first 3 commits are not present in any remote branch
      0..2
      |> Enum.map(&"HEAD~#{&1}")
      |> expect_branches("local-branch")

      # if it's called a 4th time it blows up
      stub(System, :cmd, fn "git", _anything ->
        raise "can't be called anymore!"
      end)

      # we don't find it (but it doesn't blow up) if we only check 3 commits deep
      assert {:error, :origin_commit_not_found} ==
               Git.latest_commit_also_present_in_remote("origin/main", 3)
    end

    test "it returns :error tuple when commit not found in the remote branch" do
      # the HEAD~1 commit is contained in the following branches
      list_of_branches_with_commit = """
      local-branch
      another-local-branch
      remotes/origin/foobar
      remotes/origin/quxbaz
      """

      expect_git_rev_list_count()

      expect_branches(["HEAD~0", "HEAD~1"], list_of_branches_with_commit)

      # checking only the last 2 commits
      assert {:error, :origin_commit_not_found} ==
               Git.latest_commit_also_present_in_remote("origin/main", 2)
    end

    test "it defaults to the 'origin/main' branch" do
      # the HEAD~4 commit is contained in the following branches
      list_of_branches_with_commit = """
      local-branch
      another-local-branch
      remotes/origin/foobar
      remotes/origin/main
      """

      expect_git_rev_list_count()

      0..4
      |> Enum.map(&"HEAD~#{&1}")
      |> expect_branches(list_of_branches_with_commit)

      # the last commit, HEAD~4, will be present in the remotes/origin/main branch
      # so its commit hash will be fetched via Git.commit_hash/1
      expect(System, :cmd, fn "git",
                              ["show", "HEAD~4", "--pretty=oneline", "--no-abbrev-commit"] ->
        output = File.read!("test/support/git_show_example")

        {output, 0}
      end)

      # checking the default origin/main and 200 commits
      assert {:ok,
              {"123commit_hash_dummy____git_show_example",
               [
                 "local-branch",
                 "another-local-branch",
                 "remotes/origin/foobar",
                 "remotes/origin/main"
               ]}} == Git.latest_commit_also_present_in_remote()
    end
  end

  describe "branches/1" do
    test "it returns a list of branches with the given commit" do
      commit = "1234abcd"

      expect(System, :cmd, fn "git", ["branch", "-a", "--contains", ^commit] ->
        output = File.read!("test/support/git_branch_contains_example")

        {output, 0}
      end)

      assert branches = Git.branches(commit)

      assert is_list(branches)
      assert "master" in branches
      assert "pri-706-frufra" in branches
      assert "remotes/origin/fraaaa" in branches
      assert "remotes/origin/dsfsafsagfsg17" in branches
    end
  end

  describe "commit_hash/1" do
    test "it uses the specific git reference and returns expected commit hash" do
      git_reference = "HEAD~3"

      expect(System, :cmd, fn "git",
                              ["show", ^git_reference, "--pretty=oneline", "--no-abbrev-commit"] ->
        output = File.read!("test/support/git_show_example")

        {output, 0}
      end)

      assert "123commit_hash_dummy____git_show_example" == Git.commit_hash(git_reference)
    end
  end

  describe "latest_commit_hash/0" do
    test "it returns the expected commit hash" do
      expect(System, :cmd, fn "git", ["show", "HEAD", "--pretty=oneline", "--no-abbrev-commit"] ->
        output = File.read!("test/support/git_show_example")

        {output, 0}
      end)

      assert "123commit_hash_dummy____git_show_example" == Git.latest_commit_hash()
    end
  end

  defp expect_branches(commits, last_commit_response) do
    last_commit =
      commits
      |> Enum.reverse()
      |> hd()

    Enum.map(commits, fn commit ->
      expect(System, :cmd, fn "git", ["branch", "-a", "--contains", ^commit] ->
        if commit == last_commit do
          {last_commit_response, 0}
        else
          {"local-branch", 0}
        end
      end)
    end)
  end

  defp expect_git_rev_list_count() do
    expect(System, :cmd, fn "git", ["rev-list", "--count", "HEAD"] ->
      {_number_of_commits_str = "42", 0}
    end)
  end
end
