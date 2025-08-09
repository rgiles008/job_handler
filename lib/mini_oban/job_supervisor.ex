defmodule MiniOban.JobSupervisor do
  use Supervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(_) do
    children = [
      {MiniOban.WorkerSupervisor, []},
      {MiniOban.JobQueue, max_concurrency: 4}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
