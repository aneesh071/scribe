defmodule Ueberauth.Strategy.Salesforce.OAuth do
  @moduledoc """
  OAuth2 for Salesforce.

  Add `client_id` and `client_secret` to your configuration:

      config :ueberauth, Ueberauth.Strategy.Salesforce.OAuth,
        client_id: System.get_env("SALESFORCE_CLIENT_ID"),
        client_secret: System.get_env("SALESFORCE_CLIENT_SECRET")
  """

  use OAuth2.Strategy

  @defaults [
    strategy: __MODULE__,
    site: "https://login.salesforce.com",
    authorize_url: "https://login.salesforce.com/services/oauth2/authorize",
    token_url: "https://login.salesforce.com/services/oauth2/token"
  ]

  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, __MODULE__, [])
    json_library = Ueberauth.json_library()

    opts =
      @defaults
      |> Keyword.merge(config)
      |> Keyword.merge(opts)

    opts
    |> OAuth2.Client.new()
    |> OAuth2.Client.put_serializer("application/json", json_library)
  end

  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client()
    |> OAuth2.Client.authorize_url!(params)
  end

  def get_access_token(params \\ [], opts \\ []) do
    client = client(opts)

    config = Application.get_env(:ueberauth, __MODULE__, [])

    params =
      params
      |> Keyword.put(:client_id, config[:client_id])
      |> Keyword.put(:client_secret, config[:client_secret])

    case OAuth2.Client.get_token(client, params) do
      {:ok, %{token: %{access_token: nil}}} ->
        {:error, {"no_token", "No access token received from Salesforce"}}

      {:ok, %{token: token}} ->
        {:ok, token}

      {:error, %OAuth2.Response{body: %{"error" => error, "error_description" => desc}}} ->
        {:error, {error, desc}}

      {:error, %OAuth2.Error{reason: reason}} ->
        {:error, {"oauth2_error", to_string(reason)}}
    end
  end

  def get_user_info(access_token, id_url) do
    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Accept", "application/json"}
    ]

    case Tesla.get(tesla_client(), id_url, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Tesla.Env{status: 200, body: body}} when is_binary(body) ->
        case Ueberauth.json_library().decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, "Failed to decode Salesforce user info response"}
        end

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Salesforce user info failed (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp tesla_client do
    Tesla.client([Tesla.Middleware.JSON])
  end

  # OAuth2.Strategy callbacks
  @impl true
  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  @impl true
  def get_token(client, params, headers) do
    client
    |> put_param(:grant_type, "authorization_code")
    |> put_header("Content-Type", "application/x-www-form-urlencoded")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
