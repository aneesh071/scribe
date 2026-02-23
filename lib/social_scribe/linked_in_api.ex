defmodule SocialScribe.LinkedInApi do
  @moduledoc """
  Behaviour and facade for the LinkedIn v2 API.

  Defines the callback for posting text shares.
  Delegates to the configured implementation at runtime (default: `SocialScribe.LinkedIn`).
  """

  @callback post_text_share(token :: String.t(), author_urn :: String.t(), text :: String.t()) ::
              {:ok, any()} | {:error, any()}

  def post_text_share(token, author_urn, text) do
    impl().post_text_share(token, author_urn, text)
  end

  defp impl do
    Application.get_env(:social_scribe, :linkedin_api, SocialScribe.LinkedIn)
  end
end
