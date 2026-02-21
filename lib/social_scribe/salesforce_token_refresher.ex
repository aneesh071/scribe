defmodule SocialScribe.SalesforceTokenRefresher do
  @moduledoc """
  Handles refreshing Salesforce OAuth tokens.

  Key differences from HubSpot:
  - Refresh token is stable (no rotation by default)
  - No expires_in in response — assume 2hr session timeout
  - issued_at is in milliseconds
  """

  require Logger

  @salesforce_token_url Application.compile_env(
                          :social_scribe,
                          :salesforce_token_url,
                          "https://login.salesforce.com/services/oauth2/token"
                        )
  @refresh_buffer_seconds 300
  @default_token_lifetime_seconds 7200

  @doc """
  Refreshes a Salesforce access token using the refresh token grant.

  Makes a POST request to the Salesforce token endpoint with the stored refresh token.
  Returns `{:ok, token_data}` with the new access token on success.
  """
  def refresh_token(refresh_token_string) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])

    body = %{
      grant_type: "refresh_token",
      refresh_token: refresh_token_string,
      client_id: config[:client_id],
      client_secret: config[:client_secret]
    }

    case Tesla.post(client(), @salesforce_token_url, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        Logger.error("Salesforce token refresh failed: #{status} - #{inspect(error_body)}")
        {:error, {status, error_body}}

      {:error, reason} ->
        Logger.error("Salesforce token refresh error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Refreshes the token for a credential and persists the updated tokens to the database.

  Returns `{:ok, updated_credential}` on success, `{:error, reason}` on failure.
  """
  def refresh_credential(credential) do
    case refresh_token(credential.refresh_token) do
      {:ok, response} ->
        # Salesforce refresh typically does NOT return a new refresh_token,
        # but orgs with "Rotate Refresh Tokens" enabled (opt-in since Spring 2024)
        # will return a new one. Store it defensively if present.
        attrs =
          %{
            token: response["access_token"],
            expires_at:
              DateTime.add(DateTime.utc_now(), @default_token_lifetime_seconds, :second),
            instance_url: response["instance_url"] || credential.instance_url
          }
          |> maybe_put_refresh_token(response)

        SocialScribe.Accounts.update_user_credential(credential, attrs)

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Returns the credential if its token is still valid, or refreshes it if expired.

  A token is considered expired if `expires_at` is nil or in the past.
  Returns `{:ok, credential}` with a valid token.
  """
  def ensure_valid_token(credential) do
    if token_expired_or_expiring?(credential) do
      refresh_credential(credential)
    else
      {:ok, credential}
    end
  end

  defp token_expired_or_expiring?(credential) do
    case credential.expires_at do
      nil ->
        true

      expires_at ->
        buffer = DateTime.add(DateTime.utc_now(), @refresh_buffer_seconds, :second)
        DateTime.compare(expires_at, buffer) == :lt
    end
  end

  # Salesforce orgs with "Rotate Refresh Tokens" enabled return a new refresh_token.
  # Store it if present; otherwise keep the existing one.
  defp maybe_put_refresh_token(attrs, %{"refresh_token" => new_rt}) when is_binary(new_rt),
    do: Map.put(attrs, :refresh_token, new_rt)

  defp maybe_put_refresh_token(attrs, _response), do: attrs

  defp client do
    Tesla.client([
      Tesla.Middleware.FormUrlencoded,
      Tesla.Middleware.JSON
    ])
  end
end
