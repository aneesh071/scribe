defmodule SocialScribeWeb.AuthController do
  @moduledoc """
  Handles OAuth callbacks for all providers (Google, LinkedIn, Facebook,
  HubSpot, Salesforce). Routes to credential creation or user login based
  on authentication state.
  """

  use SocialScribeWeb, :controller

  alias SocialScribe.FacebookApi
  alias SocialScribe.Accounts
  alias SocialScribeWeb.UserAuth
  plug Ueberauth

  require Logger

  @doc """
  Handles the initial request to the provider (e.g., Google).
  Ueberauth's plug will redirect the user to the provider's consent page.
  """
  def request(conn, _params) do
    render(conn, :request)
  end

  @doc """
  Handles the callback from the provider after the user has granted consent.
  """
  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "google"
      })
      when not is_nil(user) do
    Logger.info("Google OAuth callback for user #{user.id}")

    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, _credential} ->
        conn
        |> put_flash(:info, "Google account added successfully.")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not add Google account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "linkedin"
      })
      when not is_nil(user) do
    Logger.info("LinkedIn OAuth callback for user #{user.id}")

    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, _credential} ->
        conn
        |> put_flash(:info, "LinkedIn account added successfully.")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not add LinkedIn account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "facebook"
      })
      when not is_nil(user) do
    Logger.info("Facebook OAuth callback for user #{user.id}")

    case Accounts.find_or_create_user_credential(user, auth) do
      {:ok, credential} ->
        case FacebookApi.fetch_user_pages(credential.uid, credential.token) do
          {:ok, facebook_pages} ->
            facebook_pages
            |> Enum.each(fn page ->
              Accounts.link_facebook_page(user, credential, page)
            end)

          _ ->
            :ok
        end

        conn
        |> put_flash(
          :info,
          "Facebook account added successfully. Please select a page to connect."
        )
        |> redirect(to: ~p"/dashboard/settings/facebook_pages")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Could not add Facebook account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "hubspot"
      })
      when not is_nil(user) do
    Logger.info("HubSpot OAuth callback for user #{user.id}")

    hub_id = to_string(auth.uid)

    credential_attrs = %{
      user_id: user.id,
      provider: "hubspot",
      uid: hub_id,
      token: auth.credentials.token,
      refresh_token: auth.credentials.refresh_token,
      expires_at:
        (auth.credentials.expires_at && DateTime.from_unix!(auth.credentials.expires_at)) ||
          DateTime.add(DateTime.utc_now(), 3600, :second),
      email: auth.info.email
    }

    case Accounts.find_or_create_hubspot_credential(user, credential_attrs) do
      {:ok, _credential} ->
        Logger.info("HubSpot account connected for user #{user.id}, hub_id: #{hub_id}")

        conn
        |> put_flash(:info, "HubSpot account connected successfully!")
        |> redirect(to: ~p"/dashboard/settings")

      {:error, _reason} ->
        Logger.error("Failed to save HubSpot credential for user #{user.id}")

        conn
        |> put_flash(:error, "Could not connect HubSpot account.")
        |> redirect(to: ~p"/dashboard/settings")
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
        "provider" => "salesforce"
      })
      when not is_nil(user) do
    Logger.info("Salesforce OAuth for user #{user.id}")

    instance_url = get_in(auth, [Access.key(:credentials), Access.key(:other), :instance_url])

    if is_nil(instance_url) || instance_url == "" do
      Logger.error("Salesforce OAuth missing instance_url for user #{user.id}")

      conn
      |> put_flash(:error, "Could not connect Salesforce: missing instance URL.")
      |> redirect(to: ~p"/dashboard/settings")
    else
      credential_attrs = %{
        user_id: user.id,
        provider: "salesforce",
        uid: to_string(auth.uid),
        token: auth.credentials.token,
        refresh_token: auth.credentials.refresh_token,
        instance_url: instance_url,
        expires_at: DateTime.add(DateTime.utc_now(), 7200, :second),
        email: auth.info.email
      }

      case Accounts.find_or_create_salesforce_credential(user, credential_attrs) do
        {:ok, _credential} ->
          Logger.info("Salesforce account connected for user #{user.id}")

          conn
          |> put_flash(:info, "Salesforce account connected successfully!")
          |> redirect(to: ~p"/dashboard/settings")

        {:error, _reason} ->
          Logger.error("Failed to save Salesforce credential for user #{user.id}")

          conn
          |> put_flash(:error, "Could not connect Salesforce account.")
          |> redirect(to: ~p"/dashboard/settings")
      end
    end
  end

  def callback(%{assigns: %{ueberauth_auth: auth}} = conn, _params) do
    Logger.info("OAuth login callback")

    case Accounts.find_or_create_user_from_oauth(auth) do
      {:ok, user} ->
        conn
        |> UserAuth.log_in_user(user)

      {:error, _reason} ->
        Logger.error("OAuth login failed for provider callback")

        conn
        |> put_flash(:error, "There was an error signing you in.")
        |> redirect(to: ~p"/")
    end
  end

  def callback(conn, _params) do
    Logger.error("OAuth callback failed: no auth data in assigns")

    conn
    |> put_flash(:error, "There was an error signing you in. Please try again.")
    |> redirect(to: ~p"/")
  end
end
