defmodule SocialScribe.HubspotSuggestions do
  @moduledoc """
  Generates and formats HubSpot contact update suggestions by combining
  AI-extracted data with existing HubSpot contact information.
  """

  alias SocialScribe.AIContentGeneratorApi
  alias SocialScribe.HubspotApi
  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.Meetings.Meeting

  @field_categories %{
    "firstname" => "Contact Info",
    "lastname" => "Contact Info",
    "email" => "Contact Info",
    "phone" => "Contact Info",
    "mobilephone" => "Contact Info",
    "company" => "Professional Details",
    "jobtitle" => "Professional Details",
    "address" => "Address",
    "city" => "Address",
    "state" => "Address",
    "zip" => "Address",
    "country" => "Address",
    "website" => "Social & Web",
    "linkedin_url" => "Social & Web",
    "twitter_handle" => "Social & Web"
  }

  @field_labels %{
    "firstname" => "First Name",
    "lastname" => "Last Name",
    "email" => "Email",
    "phone" => "Phone",
    "mobilephone" => "Mobile Phone",
    "company" => "Company",
    "jobtitle" => "Job Title",
    "address" => "Address",
    "city" => "City",
    "state" => "State",
    "zip" => "ZIP Code",
    "country" => "Country",
    "website" => "Website",
    "linkedin_url" => "LinkedIn",
    "twitter_handle" => "Twitter"
  }

  # Allowlist derived from @field_labels — guards against AI-hallucinated field names
  @allowed_fields MapSet.new(Map.keys(@field_labels))

  # Pre-computed string→atom mapping derived from @field_labels keys.
  # Eliminates the need for String.to_existing_atom/1 + rescue.
  @field_atom_mapping Map.new(Map.keys(@field_labels), fn key -> {key, String.to_atom(key)} end)

  @doc """
  Generates suggested updates for a HubSpot contact based on a meeting transcript.

  Returns a list of suggestion maps, each containing:
  - field: the HubSpot field name
  - label: human-readable field label
  - current_value: the existing value in HubSpot (or nil)
  - new_value: the AI-suggested value
  - context: explanation of where this was found in the transcript
  - apply: boolean indicating whether to apply this update (default false)
  """
  @spec generate_suggestions(UserCredential.t(), String.t(), Meeting.t()) ::
          {:ok, %{contact: map(), suggestions: list(map())}} | {:error, any()}
  def generate_suggestions(%UserCredential{} = credential, contact_id, meeting) do
    with {:ok, contact} <- HubspotApi.get_contact(credential, contact_id),
         {:ok, ai_suggestions} <- AIContentGeneratorApi.generate_hubspot_suggestions(meeting) do
      suggestions =
        ai_suggestions
        |> Enum.filter(fn suggestion -> MapSet.member?(@allowed_fields, suggestion.field) end)
        |> Enum.map(fn suggestion ->
          field = suggestion.field
          current_value = get_contact_field(contact, field)

          %{
            field: field,
            label: Map.get(@field_labels, field, field),
            category: Map.get(@field_categories, field, "Other"),
            current_value: current_value,
            new_value: suggestion.value,
            context: suggestion.context,
            apply: true,
            has_change: current_value != suggestion.value
          }
        end)
        |> Enum.filter(fn s -> s.has_change == true end)

      {:ok, %{contact: contact, suggestions: suggestions}}
    end
  end

  @doc """
  Generates suggestions without fetching contact data.
  Useful when contact hasn't been selected yet.
  """
  @spec generate_suggestions_from_meeting(Meeting.t()) :: {:ok, list(map())} | {:error, any()}
  def generate_suggestions_from_meeting(meeting) do
    case AIContentGeneratorApi.generate_hubspot_suggestions(meeting) do
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
  Merges AI suggestions with contact data to show current vs suggested values.
  """
  @spec merge_with_contact(list(map()), map()) :: list(map())
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    Enum.map(suggestions, fn suggestion ->
      current_value = get_contact_field(contact, suggestion.field)

      %{
        suggestion
        | current_value: current_value,
          has_change: current_value != suggestion.new_value,
          apply: true
      }
    end)
    |> Enum.filter(fn s -> s.has_change == true end)
  end

  defp get_contact_field(contact, field) when is_map(contact) do
    case Map.get(@field_atom_mapping, field) do
      nil -> nil
      field_atom -> Map.get(contact, field_atom)
    end
  end

  defp get_contact_field(_, _), do: nil
end
