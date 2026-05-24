import Config

if config_env() == :test do
  # We use Req directly — disable Swoosh's built-in HTTP client
  config :swoosh, :api_client, false
end
