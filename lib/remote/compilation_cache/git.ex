defmodule Remote.CompilationCache.Git do
  @moduledoc """
  This module encapsulates Git commands that we need to check if the current code "snapshot" is cacheable or not.
  """

  @current_changes_args ~w[ls-files --others --modified --deleted --exclude-standard -t]
  @latest_commit_args ~w[show HEAD --pretty=oneline --no-abbrev-commit]
  @branches_for_commit_args ~w[branch --contains commit]

  @doc """
  Use it like this:

  Remote.CompilationCache.Git.current_changes()

  It will return a list with tuples, e.g.:

  ```
  iex()>   Remote.CompilationCache.Git.current_changes()
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

  def latest_commit_and_branches do
    latest_commit = latest_commit()

    branches = branches(latest_commit)
  end

  @doc """
  Use it like this:

  ```
  Remote.CompilationCache.Git.branches("HEAD")
  ```

  It will return a list of branches with the current commit.
  """
  def branches(commit) do
    args = @branches_for_commit_args
      |> Enum.map(fn
        "commit" -> commit
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
  Remote.CompilationCache.Git.latest_commit()
  ```

  It will return the current commit hash.
  """
  def latest_commit do
    {output, 0} = System.cmd("git", @latest_commit_args)

    [commit | _] = String.split(output, "\s", trim: true)

    commit
  end
end
