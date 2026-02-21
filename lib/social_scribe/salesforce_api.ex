defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce REST API client.

  Key differences from HubSpot:
  - Uses dynamic instance_url from credential (not fixed base URL)
  - SOQL for structured queries (not JSON filter groups)
  - PascalCase field names (FirstName, not firstname)
  - Update returns 204 No Content (not the updated object)
  - No expires_in in token response — assume 2hr session
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  require Logger

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.Salesforce.Fields
  alias SocialScribe.SalesforceTokenRefresher

  @api_version "v62.0"

  @contact_fields ~w(
    Id FirstName LastName Email Phone MobilePhone Title
    Department MailingStreet MailingCity MailingState
    MailingPostalCode MailingCountry
  )

  # Salesforce IDs are 15 or 18 character alphanumeric strings
  @salesforce_id_pattern ~r/\A[a-zA-Z0-9]{15,18}\z/

  defp client(credential) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, credential.instance_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"Authorization", "Bearer #{credential.token}"}]}
    ])
  end

  defp validate_salesforce_id(contact_id) do
    if Regex.match?(@salesforce_id_pattern, contact_id),
      do: :ok,
      else: {:error, :invalid_contact_id}
  end

  @impl true
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred ->
      escaped = escape_soql_string(query)
      fields = Enum.join(@contact_fields, ", ")

      soql =
        "SELECT #{fields}, Account.Name FROM Contact " <>
          "WHERE FirstName LIKE '%#{escaped}%' OR LastName LIKE '%#{escaped}%' " <>
          "OR Email LIKE '%#{escaped}%' " <>
          "ORDER BY LastModifiedDate DESC LIMIT 20"

      encoded = URI.encode(soql)

      case Tesla.get(client(cred), "/services/data/#{@api_version}/query/?q=#{encoded}") do
        {:ok, %Tesla.Env{status: 200, body: %{"records" => records}}} ->
          {:ok, Enum.map(records, &format_contact/1)}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @impl true
  def get_contact(%UserCredential{} = credential, contact_id)
      when is_binary(contact_id) do
    with :ok <- validate_salesforce_id(contact_id) do
      with_token_refresh(credential, fn cred ->
        fields = Enum.join(@contact_fields, ",")

        case Tesla.get(
               client(cred),
               "/services/data/#{@api_version}/sobjects/Contact/#{contact_id}?fields=#{fields}"
             ) do
          {:ok, %Tesla.Env{status: 200, body: body}} ->
            {:ok, format_contact(body)}

          {:ok, %Tesla.Env{status: 404}} ->
            {:error, :not_found}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            {:error, {:api_error, status, body}}

          {:error, reason} ->
            {:error, {:http_error, reason}}
        end
      end)
    end
  end

  @impl true
  def update_contact(%UserCredential{} = credential, contact_id, updates)
      when is_binary(contact_id) and is_map(updates) do
    with :ok <- validate_salesforce_id(contact_id) do
      with_token_refresh(credential, fn cred ->
        case Tesla.patch(
               client(cred),
               "/services/data/#{@api_version}/sobjects/Contact/#{contact_id}",
               updates
             ) do
          {:ok, %Tesla.Env{status: status}} when status in [200, 204] ->
            {:ok, :updated}

          {:ok, %Tesla.Env{status: status, body: body}} ->
            {:error, {:api_error, status, body}}

          {:error, reason} ->
            {:error, {:http_error, reason}}
        end
      end)
    end
  end

  @impl true
  def apply_updates(%UserCredential{} = credential, contact_id, updates_list)
      when is_list(updates_list) do
    applicable =
      updates_list
      |> Enum.filter(fn update -> update[:apply] == true end)
      |> Enum.into(%{}, fn update -> {update[:field], update[:new_value]} end)

    if map_size(applicable) == 0 do
      {:ok, :no_updates}
    else
      update_contact(credential, contact_id, applicable)
    end
  end

  @doc """
  Formats a Salesforce API contact record into the internal representation.
  Uses :firstname/:lastname keys to match the contact_select UI component.
  """
  @spec format_contact(map()) :: map() | nil
  def format_contact(%{"Id" => _} = record) do
    company =
      case record do
        %{"Account" => %{"Name" => name}} -> name
        _ -> nil
      end

    base =
      Enum.reduce(Fields.field_mapping(), %{}, fn {sf_field, internal_key}, acc ->
        Map.put(acc, internal_key, record[sf_field])
      end)

    base
    |> Map.put(:id, record["Id"])
    |> Map.put(:company, company)
    |> Map.put(:display_name, build_display_name(record))
  end

  def format_contact(_), do: nil

  defp build_display_name(record) do
    name =
      [record["FirstName"], record["LastName"]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    if name == "", do: record["Email"] || "Unknown", else: name
  end

  @doc false
  @spec escape_soql_string(String.t()) :: String.t()
  def escape_soql_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("_", "\\_")
    |> String.replace("%", "\\%")
  end

  defp with_token_refresh(%UserCredential{} = credential, api_fn) do
    case SalesforceTokenRefresher.ensure_valid_token(credential) do
      {:ok, refreshed_cred} ->
        case api_fn.(refreshed_cred) do
          {:error, {:api_error, 401, _body}} ->
            Logger.info("Salesforce token expired, refreshing and retrying...")

            case SalesforceTokenRefresher.refresh_credential(refreshed_cred) do
              {:ok, fresh_cred} -> api_fn.(fresh_cred)
              error -> error
            end

          other ->
            other
        end

      {:error, _} = error ->
        error
    end
  end
end
