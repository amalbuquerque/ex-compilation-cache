defmodule ExCompilationCache.Git do
  @moduledoc """
  This module encapsulates Git commands that we need to use to identify the commit to which
  it will associate the compilation "snapshot".
  """

  require Logger

  @current_changes_args ~w[ls-files --others --modified --deleted --exclude-standard -t]
  @latest_commit_args ~w[show HEAD --pretty=oneline --no-abbrev-commit]
  @commit_list_args ~w[log --oneline --graph --no-abbrev-commit <range>]
  @branches_for_commit_args ~w[branch -a --contains <commit>]
  @number_of_commits_args ~w[rev-list --count <commit>]

  @type commit :: String.t()
  @type branch :: String.t()

  @doc """
  Use it like this:

  ExCompilationCache.Git.current_changes()

  It will return a list with tuples, e.g.:

  ```
  iex()> ExCompilationCache.Git.current_changes()
  [
    {"?", "20240212_after_30000_compilation_succeeded.output"},
    {"?", "Callback_CAT.crt"},
    {"?", "Callback_CAT_20240320.crt"},
    {"?", "Callback_PROD.crt"}
  ]
  ```

  In essence, if the file shows up in this list it was deemed by Git to have been changed when compared with HEAD.

  The first element of the tuple can be one of (for more info about these statuses check https://git-scm.com/docs/git-ls-files#Documentation/git-ls-files.txt--t):

    * H, tracked file that is not either unmerged or skip-worktree
    * S, tracked file that is skip-worktree
    * M, tracked file that is unmerged
    * R, tracked file with unstaged removal/deletion
    * C, tracked file with unstaged modification/change
    * K, untracked paths which are part of file/directory conflicts which prevent checking out tracked files
    * ?, untracked file
    * U, file with resolve-undo information
  """
  @spec current_changes :: [{String.t(), Path.t()}]
  def current_changes do
    {output, 0} = System.cmd("git", @current_changes_args)

    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn
      "" ->
        []

      <<mode::8>> <> " " <> file_path ->
        mode_str = to_string([mode])

        [{mode_str, file_path}]
    end)
  end

  @doc """
  It will return the latest 100 commits (max) from a given commit.

  It relies on the output of `git log --oneline --graph --no-abbrev-commit <commit>~<number_of_commits>..<commit>`, and returns all commits in the graph starting with `*`.
  """
  def commit_list(latest_commit, number_of_commits_max \\ 100) do
    number_of_commits = min(number_of_commits_max, number_of_commits_branch(latest_commit)) - 1

    args =
      Enum.map(@commit_list_args, fn
        "<range>" ->
          "#{latest_commit}~#{number_of_commits}..#{latest_commit}"

        arg ->
          arg
      end)

    {output, 0} = System.cmd("git", args)

    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn
      "" ->
        []

      "*" <> _ = commit_line ->
        commit = extract_commit_from_list_line(commit_line)

        if is_nil(commit) do
          Logger.warning("Problem extracting commit from: #{commit_line}")
          []
        else
          [commit]
        end

      _ ->
        []
    end)
  end

  defp extract_commit_from_list_line(commit_line) do
    captures =
      Regex.named_captures(~r/(?<prefix>[*|\/_\ ]+)(?<commit>[[:xdigit:]]+) .+/, commit_line)

    get_in(captures, ["commit"])
  end

  @doc """
  It will check the latest 200 commits (max) and return the most recent commit (starting from HEAD) which also exists in the remote
  branch (usually `origin/main` or `origin/master`).

  It can be used to identify the first commit from which we should check if cache artifacts are available.

  Use it like this:

  ```
  ExCompilationCache.Git.latest_commit_also_present_in_remote()
  ExCompilationCache.Git.latest_commit_also_present_in_remote("origin/master")
  ```
  """
  @spec latest_commit_also_present_in_remote(String.t(), non_neg_integer()) ::
          {:ok, {commit(), [branch()]}} | {:error, :origin_commit_not_found}
  def latest_commit_also_present_in_remote(
        remote_branch_name \\ "origin/main",
        number_of_commits_max \\ 200
      ) do
    full_remote_branch_name = "remotes/#{remote_branch_name}"

    number_of_commits = min(number_of_commits_max, number_of_commits_branch("HEAD"))

    result =
      Enum.reduce_while(0..(number_of_commits - 1), nil, fn commit_number, _acc ->
        commit_reference = "HEAD~#{commit_number}"

        branches = branches(commit_reference)

        Logger.debug(
          "Checking branches of '#{commit_reference}' for '#{full_remote_branch_name}': #{inspect(branches)}"
        )

        if full_remote_branch_name in branches do
          {:halt, {commit_hash(commit_reference), branches}}
        else
          {:cont, nil}
        end
      end)

    case result do
      nil ->
        {:error, :origin_commit_not_found}

      result ->
        {:ok, result}
    end
  end

  @doc """
  Use it like this:

  ```
  ExCompilationCache.Git.branches("HEAD")
  ExCompilationCache.Git.branches("HEAD~3")

  commit = ExCompilationCache.Git.latest_commit()
  ExCompilationCache.Git.branches(commit)
  ```

  It will return a list of branches with the given commit.
  """
  def branches(commit) do
    args =
      @branches_for_commit_args
      |> Enum.map(fn
        "<commit>" -> commit
        arg -> arg
      end)

    {output, 0} = System.cmd("git", args)

    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn
      "* " <> current_branch ->
        [current_branch]

      other_branch ->
        if String.contains?(other_branch, " -> ") do
          []
        else
          [String.trim(other_branch)]
        end
    end)
  end

  @doc """
  Use it like this:

  ```
  ExCompilationCache.Git.latest_commit_hash()
  ```

  It will return the current commit hash.
  """
  def latest_commit_hash do
    {output, 0} = System.cmd("git", @latest_commit_args)

    [commit | _] = String.split(output, "\s", trim: true)

    commit
  end

  @doc """
  Use it like this:

  ```
  ExCompilationCache.Git.commit_hash("HEAD~1")
  ```

  It will return the given commit hash.
  """
  def commit_hash(reference) do
    commit_args =
      Enum.map(@latest_commit_args, fn
        "HEAD" ->
          reference

        arg ->
          arg
      end)

    {output, 0} = System.cmd("git", commit_args)

    [commit | _] = String.split(output, "\s", trim: true)

    commit
  end

  def number_of_commits_branch(current_commit) do
    args =
      Enum.map(@number_of_commits_args, fn
        "<commit>" ->
          current_commit

        arg ->
          arg
      end)

    {number_of_commits_str, 0} = System.cmd("git", args)

    {number_of_commits, ""} =
      number_of_commits_str
      |> String.trim()
      |> Integer.parse()

    number_of_commits
  end
end
