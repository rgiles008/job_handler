defmodule MiniOban.JobQueue do
  use GenServer

  @default_concurrency 4
  @table :mini_oban_jobs

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def enqueue(job, opts \\ []) do
    job = %{
      func: job,
      attempts: Keyword.get(opts, :attempts, 3)
    }

    GenServer.call(__MODULE__, {:enqueue, job})
  end

  def mark_done(job_id, status), do: GenServer.cast(__MODULE__, {:job_done, job_id, status})

  def mark_retry(job_id, reason), do: GenServer.cast(__MODULE__, {:job_retry, job_id, reason})

  def status(job_id) do
    case :ets.lookup(@table, job_id) do
      [{^job_id, status, inserted_at, finished_at, attempts_run, last_error}] ->
        %{
          job_id: job_id,
          status: status,
          inserted_at: inserted_at,
          finished_at: finished_at,
          attempts_run: attempts_run,
          last_error: last_error
        }

      [] ->
        :not_found
    end
  end

  def stats do
    :ets.foldl(
      fn {_id, status, _ins, _fin, _att, _err}, acc ->
        Map.update(acc, status, 1, &(&1 + 1))
      end,
      %{},
      @table
    )
  end

  def init(opts) do
    _ = :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

    state = %{
      queue: :queue.new(),
      running: %{},
      max_concurrency: opts[:max_concurrency] || @default_concurrency
    }

    {:ok, state}
  end

  def handle_call({:enqueue, job}, _from, state) do
    job_id = :erlang.unique_integer([:monotonic, :positive])
    inserted_at = System.monotonic_time(:millisecond)
    :ets.insert(@table, {job_id, :queued, inserted_at, nil, 0, nil})

    state =
      %{state | queue: :queue.in(Map.put(job, :job_id, job_id), state.queue)}
      |> maybe_start_next()

    {:reply, job_id, maybe_start_next(state)}
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    new_state = %{state | running: Map.delete(state.running, ref)}
    {:noreply, maybe_start_next(new_state)}
  end

  def handle_cast({:job_done, job_id, result}, state) do
    finished_at = System.monotonic_time(:millisecond)

    case result do
      :ok ->
        update_status(@table, job_id, :running, {:set, :ok, finished_at, :no_change, nil})

      {:error, reason} ->
        update_status(
          @table,
          job_id,
          :running,
          {:set, :error, finished_at, :no_change, inspect(reason)}
        )
    end

    {:noreply, state}
  end

  def handle_cast({:job_retry, job_id, reason}, state) do
    update_status(
      @table,
      job_id,
      :running,
      {:keep_status, :no_time, :inc_attempts, inspect(reason)}
    )

    {:noreply, state}
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

  defp update_status(table, job_id, _expected_status, action) do
    case :ets.lookup(table, job_id) do
      [{^job_id, status, ins, fin, attempts, err}] ->
        {new_status, new_fin, new_attempts, new_err} =
          case action do
            {:set, s, finished_at, :no_change, e} -> {s, finished_at, attempts, e}
            {:keep_status, :no_time, :inc_attempts, e} -> {status, fin, attempts + 1, e || err}
          end

        :ets.insert(table, {job_id, new_status, ins, new_fin, new_attempts, new_err})

      _ ->
        :noop
    end
  end
end
