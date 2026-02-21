defmodule SocialScribe.SalesforceSuggestions do
  @moduledoc """
  Generates AI-powered suggestions for Salesforce contact updates
  based on meeting transcripts.
  """

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.Meetings.Meeting
  alias SocialScribe.Salesforce.Fields

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

  # Allowlist derived from @field_labels — guards against AI-hallucinated field names
  @allowed_fields MapSet.new(Map.keys(@field_labels))

  @doc """
  Generates suggestions from a meeting transcript without contact data.
  Called first, then merged with contact after selection.
  """
  @spec generate_suggestions_from_meeting(Meeting.t()) :: {:ok, list(map())} | {:error, any()}
  def generate_suggestions_from_meeting(meeting) do
    case AIContentGeneratorApi.generate_salesforce_suggestions(meeting) do
      {:ok, ai_suggestions} ->
        suggestions =
          ai_suggestions
          |> Enum.filter(fn suggestion -> MapSet.member?(@allowed_fields, suggestion.field) end)
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
  @spec merge_with_contact(list(map()), map()) :: list(map())
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    suggestions
    |> Enum.map(fn suggestion ->
      contact_key = Map.get(Fields.field_mapping(), suggestion.field)
      current_value = if contact_key, do: Map.get(contact, contact_key), else: nil

      %{
        suggestion
        | current_value: current_value,
          has_change: current_value != suggestion.new_value,
          apply: true
      }
    end)
    |> Enum.filter(fn suggestion -> suggestion.has_change == true end)
  end
end
