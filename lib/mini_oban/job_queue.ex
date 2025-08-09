defmodule MiniOban.JobQueue do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :queue.new(), name: __MODULE__)
  end

  def enqueue(job, opts \\ []) do
    job = %{
      func: job,
      attempts: Keyword.get(opts, :attempts, 3)
    }

    GenServer.cast(__MODULE__, {:enqueue, job})
  end

  def init(state) do
    {:ok, state}
  end

  def handle_cast({:enqueue, job}, state) do
    state = :queue.in(state, job)
    {:ok, _pid} = MiniOban.WorkerSupervisor.process(job)
    {:noreply, state}
  end
end
