defmodule SocialScribe.SalesforceSuggestions do
  @moduledoc """
  Generates AI-powered suggestions for Salesforce contact updates
  based on meeting transcripts.
  """

  alias SocialScribe.AIContentGeneratorApi

  @field_labels %{
    "FirstName" => "First Name",
    "LastName" => "Last Name",
    "Email" => "Email",
    "Phone" => "Phone",
    "MobilePhone" => "Mobile Phone",
    "Title" => "Job Title",
    "Department" => "Department",
    "MailingStreet" => "Mailing Street",
    "MailingCity" => "Mailing City",
    "MailingState" => "Mailing State",
    "MailingPostalCode" => "Mailing Postal Code",
    "MailingCountry" => "Mailing Country"
  }

  # Maps Salesforce PascalCase field names to internal contact atom keys
  # These must match the keys from SalesforceApi.format_contact/1
  @field_to_contact_key %{
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

  # Category grouping for UI display (matches reference design)
  @field_categories %{
    "FirstName" => "Contact Info",
    "LastName" => "Contact Info",
    "Email" => "Contact Info",
    "Phone" => "Contact Info",
    "MobilePhone" => "Contact Info",
    "Title" => "Professional Details",
    "Department" => "Professional Details",
    "MailingStreet" => "Mailing Address",
    "MailingCity" => "Mailing Address",
    "MailingState" => "Mailing Address",
    "MailingPostalCode" => "Mailing Address",
    "MailingCountry" => "Mailing Address"
  }

  @doc """
  Generates suggestions from a meeting transcript without contact data.
  Called first, then merged with contact after selection.
  """
  def generate_suggestions_from_meeting(meeting) do
    case AIContentGeneratorApi.generate_salesforce_suggestions(meeting) do
      {:ok, ai_suggestions} ->
        suggestions =
          ai_suggestions
          |> Enum.map(fn suggestion ->
            %{
              field: suggestion.field,
              label: Map.get(@field_labels, suggestion.field, suggestion.field),
              category: Map.get(@field_categories, suggestion.field, "Other"),
              current_value: nil,
              new_value: suggestion.value,
              context: Map.get(suggestion, :context),
              timestamp: Map.get(suggestion, :timestamp),
              apply: true,
              has_change: true
            }
          end)

        {:ok, suggestions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Merges AI suggestions with actual contact data.
  Fills in current_value and filters out suggestions where value hasn't changed.
  """
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    suggestions
    |> Enum.map(fn suggestion ->
      contact_key = Map.get(@field_to_contact_key, suggestion.field)
      current_value = if contact_key, do: Map.get(contact, contact_key), else: nil

      %{
        suggestion
        | current_value: current_value,
          has_change: current_value != suggestion.new_value,
          apply: true
      }
    end)
    |> Enum.filter(& &1.has_change)
  end
end
