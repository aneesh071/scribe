defmodule SocialScribe.SalesforceApiBehaviour do
  @moduledoc """
  Behaviour for the Salesforce API.
  Delegates to the configured implementation (real or mock).
  """

  alias SocialScribe.Accounts.UserCredential

  @callback search_contacts(credential :: UserCredential.t(), query :: String.t()) ::
              {:ok, list(map())} | {:error, any()}

  @callback get_contact(credential :: UserCredential.t(), contact_id :: String.t()) ::
              {:ok, map()} | {:error, any()}

  @callback update_contact(
              credential :: UserCredential.t(),
              contact_id :: String.t(),
              updates :: map()
            ) ::
              {:ok, :updated} | {:error, any()}

  @callback apply_updates(
              credential :: UserCredential.t(),
              contact_id :: String.t(),
              updates_list :: list(map())
            ) ::
              {:ok, :updated | :no_updates} | {:error, any()}

  def search_contacts(credential, query) do
    impl().search_contacts(credential, query)
  end

  def get_contact(credential, contact_id) do
    impl().get_contact(credential, contact_id)
  end

  def update_contact(credential, contact_id, updates) do
    impl().update_contact(credential, contact_id, updates)
  end

  def apply_updates(credential, contact_id, updates_list) do
    impl().apply_updates(credential, contact_id, updates_list)
  end

  defp impl do
    Application.get_env(:social_scribe, :salesforce_api, SocialScribe.SalesforceApi)
  end
end
