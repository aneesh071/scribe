defmodule SocialScribe.Salesforce.Fields do
  @moduledoc """
  Shared Salesforce field definitions used by both SalesforceApi and SalesforceSuggestions.

  Maps Salesforce PascalCase field names to internal atom keys matching the
  contact_select UI component's expected format (:firstname, :lastname, etc.).
  """

  @field_mapping %{
    "FirstName" => :firstname,
    "LastName" => :lastname,
    "Email" => :email,
    "Phone" => :phone,
    "MobilePhone" => :mobilephone,
    "Title" => :jobtitle,
    "Department" => :department,
    "MailingStreet" => :address,
    "MailingCity" => :city,
    "MailingState" => :state,
    "MailingPostalCode" => :zip,
    "MailingCountry" => :country
  }

  def field_mapping, do: @field_mapping
end
