defmodule SocialScribe.TokenRefresherApi do
  @moduledoc """
  Behaviour and facade for OAuth token refresh.

  Defines the callback for refreshing expired OAuth tokens via the Google OAuth2 endpoint.
  Delegates to the configured implementation at runtime (default: `SocialScribe.TokenRefresher`).
  """

  @callback refresh_token(refresh_token :: String.t()) :: {:ok, map()} | {:error, any()}

  def refresh_token(refresh_token), do: impl().refresh_token(refresh_token)

  defp impl,
    do: Application.get_env(:social_scribe, :token_refresher_api, SocialScribe.TokenRefresher)
end
