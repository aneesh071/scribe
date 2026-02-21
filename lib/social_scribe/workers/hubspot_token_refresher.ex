defmodule SocialScribe.Workers.HubspotTokenRefresher do
  @moduledoc """
  Oban worker that proactively refreshes HubSpot OAuth tokens before they expire.
  Runs every 5 minutes and refreshes tokens expiring within 10 minutes.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias SocialScribe.Accounts
  alias SocialScribe.HubspotTokenRefresher

  require Logger

  @refresh_threshold_minutes 10

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("Running proactive HubSpot token refresh check...")

    threshold = DateTime.add(DateTime.utc_now(), @refresh_threshold_minutes, :minute)
    expiring_credentials = Accounts.list_expiring_credentials("hubspot", threshold)

    case expiring_credentials do
      [] ->
        Logger.debug("No HubSpot tokens expiring soon")
        :ok

      credentials ->
        Logger.info("Found #{length(credentials)} HubSpot token(s) expiring soon, refreshing...")
        refresh_all(credentials)
    end
  end

  defp refresh_all(credentials) do
    Enum.each(credentials, fn credential ->
      case HubspotTokenRefresher.refresh_credential(credential) do
        {:ok, _updated} ->
          Logger.info("Proactively refreshed HubSpot token for credential #{credential.id}")

        {:error, reason} ->
          Logger.error(
            "Failed to proactively refresh HubSpot token for credential #{credential.id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end
end
