defmodule MiniOban.JobQueueTest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  defp wait_for(fun, timeout_ms \\ 2_000) do
    start = System.monotonic_time(:millisecond)
    do_wait_for(fun, start, timeout_ms)
  end

  defp do_wait_for(fun, start_ms, timeout_ms) do
    case fun.() do
      true ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) - start_ms > timeout_ms do
          flunk("wait_for/2 timed out")
        else
          Process.sleep(20)
          do_wait_for(fun, start_ms, timeout_ms)
        end
    end
  end

  setup do
    MiniOban.JobQueue.reset!()
    :ok
  end

  test "enqueue returns job_id and status flow to :ok" do
    job_id =
      MiniOban.JobQueue.enqueue(
        fn ->
          Process.sleep(100)
          :ok
        end,
        attempts: 3
      )

    assert is_integer(job_id)

    wait_for(fn ->
      case MiniOban.JobQueue.status(job_id) do
        %{status: s} when s in [:queued, :running, :ok] -> true
        _ -> false
      end
    end)

    wait_for(fn ->
      case MiniOban.JobQueue.status(job_id) do
        %{status: :ok} -> true
        _ -> false
      end
    end)

    status = MiniOban.JobQueue.status(job_id)
    assert status.status == :ok
    assert status.attempts_run >= 0
  end

  test "retries and marks exhausted on persistent failure" do
    job_id =
      MiniOban.JobQueue.enqueue(
        fn ->
          raise "boom"
        end,
        attempts: 2
      )

    # Eventually ends as :error with attempts_run bumped
    wait_for(fn ->
      case MiniOban.JobQueue.status(job_id) do
        %{status: :error, attempts_run: n} when n >= 2 -> true
        _ -> false
      end
    end)

    status = MiniOban.JobQueue.status(job_id)
    assert status.status == :error
    assert status.attempts_run >= 2
    assert is_binary(status.last_error) or is_nil(status.last_error)
  end

  test "stats aggregates counts by status" do
    MiniOban.JobQueue.set_max_concurrency(2)

    ok_id =
      MiniOban.JobQueue.enqueue(
        fn ->
          :ok
        end,
        attempts: 1
      )

    err_id =
      MiniOban.JobQueue.enqueue(
        fn ->
          raise "nope"
        end,
        attempts: 1
      )

    # Wait for everything to finish (no running, no queued)
    assert :ok == MiniOban.JobQueue.drain(7_000)

    # Now the statuses are stable
    assert %{status: :ok} = MiniOban.JobQueue.status(ok_id)
    assert %{status: :error} = MiniOban.JobQueue.status(err_id)

    stats = MiniOban.JobQueue.stats()
    assert (stats[:ok] || 0) >= 1
    assert (stats[:error] || 0) >= 1
  end
end
