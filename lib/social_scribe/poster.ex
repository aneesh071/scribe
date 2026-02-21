defmodule SocialScribe.Poster do
  @moduledoc """
  Dispatches social media posts to connected platforms (LinkedIn, Facebook).

  Reads the user's OAuth credentials and calls the appropriate platform API.
  """

  alias SocialScribe.LinkedInApi
  alias SocialScribe.FacebookApi
  alias SocialScribe.Accounts

  @doc """
  Posts generated content to the specified social media platform.

  Accepts `:linkedin` or `:facebook` as the platform, looks up the user's
  stored OAuth credential, and dispatches the content via the platform API.
  Returns `{:ok, response}` on success or `{:error, reason}` on failure.
  """
  def post_on_social_media(platform, generated_content, current_user) do
    case platform do
      :linkedin -> post_on_linkedin(generated_content, current_user)
      :facebook -> post_on_facebook(generated_content, current_user)
      _ -> {:error, "Unsupported platform"}
    end
  end

  defp post_on_linkedin(generated_content, current_user) do
    case Accounts.get_user_linkedin_credential(current_user) do
      nil ->
        {:error, "LinkedIn credential not found"}

      user_credential ->
        LinkedInApi.post_text_share(
          user_credential.token,
          user_credential.uid,
          generated_content
        )
    end
  end

  defp post_on_facebook(generated_content, current_user) do
    case Accounts.get_user_selected_facebook_page_credential(current_user) do
      nil ->
        {:error, "Facebook page credential not found"}

      facebook_page_credential ->
        FacebookApi.post_message_to_page(
          facebook_page_credential.facebook_page_id,
          facebook_page_credential.page_access_token,
          generated_content
        )
    end
  end
end
