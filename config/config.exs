import Config

config :logger, :console,
  format: "[$level] job_id=#{:job_id} $message\n",
  metadata: [:job_id]
