defmodule ExCompilationCache.Git do
  @moduledoc """
  This module encapsulates Git commands that we need to use to identify the commit to which
  it will associate the compilation "snapshot".
  """

  @current_changes_args ~w[ls-files --others --modified --deleted --exclude-standard -t]
  @latest_commit_args ~w[show HEAD --pretty=oneline --no-abbrev-commit]
  @branches_for_commit_args ~w[branch -a --contains <commit>]

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
  It will check the latest 20 commits and return the first commit (starting from HEAD) which also exists in the remote
  branch (usually `origin/main` or `origin/master`).

  Use it like this:

  ```
  ExCompilationCache.Git.latest_commit_also_present_in_remote()
  ExCompilationCache.Git.latest_commit_also_present_in_remote("origin/master")
  ```
  """
  @spec latest_commit_also_present_in_remote(String.t(), non_neg_integer()) :: {:ok, {commit(), [branch()]}} | {:error, :origin_commit_not_found}
  def latest_commit_also_present_in_remote(remote_branch_name \\ "origin/main", number_of_commits \\ 20) do
    full_remote_branch_name = "remotes/#{remote_branch_name}"

    result = Enum.reduce_while(0..(number_of_commits-1), nil, fn commit_number, _acc ->
      commit_reference = "HEAD~#{commit_number}"

      branches = branches(commit_reference)

      if(full_remote_branch_name in branches) do
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
    |> Enum.map(fn
      "* " <> current_branch ->
        current_branch

      other_branch ->
        String.trim(other_branch)
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
    commit_args = Enum.map(@latest_commit_args, fn
      "HEAD" ->
        reference

      arg ->
        arg
    end)

    {output, 0} = System.cmd("git", commit_args)

    [commit | _] = String.split(output, "\s", trim: true)

    commit
  end
end
