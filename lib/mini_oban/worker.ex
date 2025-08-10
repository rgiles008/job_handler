defmodule MiniOban.Worker do
  use GenServer

  require Logger

  def start_link(job), do: GenServer.start_link(__MODULE__, job)

  def init(%{attempts: attempts} = job) do
    Logger.metadata(job_id: job.job_id)
    Logger.info("job #{job.job_id} starting (attempts=#{attempts})")

    send(self(), :run)
    {:ok, Map.put(job, :attempts_left, attempts)}
  end

  def handle_info(:run, %{attempts_left: 0, job_id: job_id} = state) do
    Logger.error("job #{job_id} exhausted all retries")

    MiniOban.JobQueue.mark_done(job_id, {:error, :exhausted})
    {:stop, :normal, state}
  end

  def handle_info(:run, %{attempts_left: n, func: fun, job_id: job_id} = state) do
    case apply_fun(fun) do
      :ok ->
        Logger.info("job #{job_id} done")

        MiniOban.JobQueue.mark_done(job_id, :ok)
        {:stop, :normal, state}

      {:error, reason} ->
        Logger.warning("job #{job_id} failed: #{inspect(reason)}; retrying (#{n - 1} left)")

        MiniOban.JobQueue.mark_retry(job_id, reason)
        Process.send_after(self(), :run, backoff(n))
        {:noreply, %{state | attempts_left: n - 1}}
    end
  end

  def apply_fun(function) do
    try do
      function.()
      :ok
    rescue
      e ->
        {:error, e}
    end
  end

  def backoff(n) do
    (:math.pow(2, 3 - n) * 100) |> round()
  end
end
