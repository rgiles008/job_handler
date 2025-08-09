defmodule MiniOban.WorkerSupervisor do
  use DynamicSupervisor

  def start_link(_), do: DynamicSupervisor.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def process(job) do
    DynamicSupervisor.start_child(__MODULE__, {MiniOban.Worker, job})
  end
end
