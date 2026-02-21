defmodule SocialScribe.Workers.SalesforceTokenRefresher do
  @moduledoc """
  Oban cron worker that proactively refreshes expiring Salesforce tokens.
  Runs every 30 minutes. Salesforce access tokens last ~2 hours.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias SocialScribe.Accounts
  alias SocialScribe.SalesforceTokenRefresher

  require Logger

  @refresh_threshold_minutes 60

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("Running proactive Salesforce token refresh check...")

    threshold = DateTime.add(DateTime.utc_now(), @refresh_threshold_minutes, :minute)
    credentials = Accounts.list_expiring_credentials("salesforce", threshold)

    case credentials do
      [] ->
        Logger.debug("No Salesforce tokens expiring soon")
        :ok

      credentials ->
        Logger.info(
          "Found #{length(credentials)} Salesforce token(s) expiring soon, refreshing..."
        )

        refresh_all(credentials)
    end
  end

  defp refresh_all(credentials) do
    Enum.each(credentials, fn credential ->
      case SalesforceTokenRefresher.refresh_credential(credential) do
        {:ok, _} ->
          Logger.info("Refreshed Salesforce token for credential #{credential.id}")

        {:error, reason} ->
          Logger.error(
            "Failed to refresh Salesforce token for credential #{credential.id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end
end
