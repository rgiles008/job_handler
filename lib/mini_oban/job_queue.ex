defmodule MiniOban.JobQueue do
  use GenServer

  @default_concurrency 4

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def enqueue(job, opts \\ []) do
    job = %{
      func: job,
      attempts: Keyword.get(opts, :attempts, 3)
    }

    GenServer.cast(__MODULE__, {:enqueue, job})
  end

  def init(opts) do
    state = %{
      queue: :queue.new(),
      running: %{},
      max_concurrency: opts[:max_concurrency] || @default_concurrency
    }

    {:ok, state}
  end

  def handle_cast({:enqueue, job}, state) do
    state = %{state | queue: :queue.in(job, state.queue)}
    {:noreply, maybe_start_next(state)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    new_state = %{state | running: Map.delete(state.running, ref)}
    {:noreply, maybe_start_next(new_state)}
  end

  def maybe_start_next(state) do
    running_count = map_size(state.running)

    cond do
      running_count >= state.max_concurrency ->
        state

      true ->
        case :queue.out(state.queue) do
          {:empty, _q} ->
            state

          {{:value, job}, q2} ->
            {:ok, pid} = MiniOban.WorkerSupervisor.process(job)
            ref = Process.monitor(pid)

            state
            |> Map.put(:queue, q2)
            |> Map.update!(:running, &Map.put(&1, ref, :running))
            |> maybe_start_next()
        end
    end
  end
end
