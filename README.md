# ExCompilationCache

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `ex_compilation_cache` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_compilation_cache, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/compilation_cache>.

## TODO

- `BuildCache` creation for a particular Git commit should have the commit timestamp as its `timestamp` (currently the `timestamp` is only filled when parsing the `BuildCache` from the artifact name stored remotely)
- Perform `git fetch` of remote branch before any operation to make sure local has the latest info about the remote branch
- `BuildCache` also tracks the Elixir version
- Only fetch the `:ex_compilation_cache` library and its dependencies + compile it (instead of requiring all deps to be downloaded and compiled before calling the `maybe.compile` Mix.Task) (we might need to read the `mix.lock` to understand the deps graph we need and then do `deps.get foo, deps.compile foo` for each dependency)
