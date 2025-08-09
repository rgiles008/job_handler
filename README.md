# MiniOban

This is just a playaround stab at implementing an oban like job processor
using GenServers and other Supervision tooling. It can receive a function or a struct
and jobs are processing dynamically.

## Testing it out

1. in iex run `MiniOban.JobQueue.enqueue(fn -> IO.puts("Im a job") end)`
2. or you can do something like
```elixir
MiniOban.JobQueue.enqueue(fn ->
    IO.puts("job #{i} starting")
    Process.sleep(300)
    if :rand.uniform() < 0.2, do: raise("boom #{i}")
    IO.puts("job #{i} done")
  end, attempts: 3)
```

## Notes
I did initalize the GenServer with a :queue as its initial state but its not used.
Right now the implementation is kind of a fire and forget where jobs are spun up dynamically
I will push another version to use the queue and add testing around that



Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/mini_oban>.

