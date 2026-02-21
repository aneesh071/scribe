defmodule Ueberauth.Strategy.Salesforce do
  @moduledoc """
  Salesforce Strategy for Ueberauth.

  Implements OAuth 2.0 authorization code flow against Salesforce's
  login.salesforce.com endpoints. Extracts `instance_url` from the token
  response for use as the per-org base URL for all subsequent API calls.

  ## Configuration

      config :ueberauth, Ueberauth.Strategy.Salesforce.OAuth,
        client_id: System.get_env("SALESFORCE_CLIENT_ID"),
        client_secret: System.get_env("SALESFORCE_CLIENT_SECRET")

  Default scope: `"api refresh_token"`.
  """

  use Ueberauth.Strategy,
    uid_field: :user_id,
    default_scope: "api refresh_token",
    oauth2_module: Ueberauth.Strategy.Salesforce.OAuth

  alias Ueberauth.Auth.{Credentials, Info, Extra}

  @impl true
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    params =
      [scope: scopes, redirect_uri: callback_url(conn)]
      |> with_state_param(conn)

    redirect!(conn, Ueberauth.Strategy.Salesforce.OAuth.authorize_url!(params))
  end

  @impl true
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    case Ueberauth.Strategy.Salesforce.OAuth.get_access_token(
           code: code,
           redirect_uri: callback_url(conn)
         ) do
      {:ok, token} ->
        conn
        |> put_private(:salesforce_token, token)
        |> fetch_user(token)

      {:error, {error_code, error_description}} ->
        set_errors!(conn, [error(error_code, error_description)])
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @impl true
  def handle_cleanup!(conn) do
    conn
    |> put_private(:salesforce_token, nil)
    |> put_private(:salesforce_user, nil)
  end

  @impl true
  def uid(conn) do
    uid_field =
      conn
      |> option(:uid_field)
      |> to_string()

    conn.private[:salesforce_user][uid_field]
  end

  @impl true
  def credentials(conn) do
    token = conn.private[:salesforce_token]

    %Credentials{
      token: token.access_token,
      refresh_token: token.refresh_token,
      token_type: "Bearer",
      expires: true,
      expires_at: token.expires_at,
      other: %{
        instance_url: token.other_params["instance_url"],
        issued_at: token.other_params["issued_at"]
      }
    }
  end

  @impl true
  def info(conn) do
    user = conn.private[:salesforce_user] || %{}

    %Info{
      email: user["email"],
      name: user["name"]
    }
  end

  @impl true
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private[:salesforce_token],
        user: conn.private[:salesforce_user]
      }
    }
  end

  defp fetch_user(conn, token) do
    # The "id" field in token response is the identity URL
    id_url = token.other_params["id"]

    if id_url do
      case Ueberauth.Strategy.Salesforce.OAuth.get_user_info(token.access_token, id_url) do
        {:ok, user} ->
          put_private(conn, :salesforce_user, user)

        {:error, reason} ->
          set_errors!(conn, [error("user_info", reason)])
      end
    else
      set_errors!(conn, [error("missing_id_url", "No identity URL in Salesforce token response")])
    end
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end
end
