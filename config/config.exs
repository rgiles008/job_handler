import Config

config :logger, :console,
  format: "[$level] $metadata$message\n",
  metadata: [:job_id]
