defmodule MiniOban.Worker do
  use GenServer

  def start_link(job), do: GenServer.start_link(__MODULE__, job)

  def init(%{attempts: attempts} = job) do
    send(self(), :run)
    {:ok, Map.put(job, :attempts_left, attempts)}
  end

  def handle_info(:run, %{attempts_left: 0} = state) do
    {:stop, :normal, state}
  end

  def handle_info(:run, %{attempts_left: n} = state) do
    case apply_fun(state.func) do
      :ok ->
        {:stop, :normal, state}

      {:error, _reason} ->
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
