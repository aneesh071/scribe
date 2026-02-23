defmodule SocialScribe.SalesforceSuggestionsPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias SocialScribe.SalesforceSuggestions

  @salesforce_fields ~w(FirstName LastName Email Phone MobilePhone Title Department MailingStreet MailingCity MailingState MailingPostalCode MailingCountry)

  # Maps Salesforce field names to contact atom keys (must match SalesforceApi.format_contact)
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

  defp suggestion_generator do
    gen all(
          field <- member_of(@salesforce_fields),
          value <- string(:alphanumeric, min_length: 1, max_length: 50),
          context <- string(:alphanumeric, min_length: 1, max_length: 100)
        ) do
      %{
        field: field,
        label: field,
        category: "Test Category",
        current_value: nil,
        new_value: value,
        context: context,
        timestamp: "01:00",
        apply: false,
        has_change: false
      }
    end
  end

  defp contact_generator do
    gen all(
          firstname <- string(:alphanumeric, min_length: 1, max_length: 20),
          lastname <- string(:alphanumeric, min_length: 1, max_length: 20),
          email <- string(:alphanumeric, min_length: 1, max_length: 30)
        ) do
      %{
        id: "003xx",
        firstname: firstname,
        lastname: lastname,
        email: email,
        phone: nil,
        mobilephone: nil,
        jobtitle: nil,
        department: nil,
        address: nil,
        city: nil,
        state: nil,
        zip: nil,
        country: nil,
        company: nil,
        display_name: "#{firstname} #{lastname}"
      }
    end
  end

  property "never returns suggestions where new_value equals contact's current value" do
    check all(
            suggestions <- list_of(suggestion_generator(), min_length: 0, max_length: 10),
            contact <- contact_generator()
          ) do
      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      for suggestion <- result do
        contact_key = Map.get(@field_to_contact_key, suggestion.field)
        current = if contact_key, do: Map.get(contact, contact_key), else: nil
        assert suggestion.new_value != current
      end
    end
  end

  property "current_value matches the contact's actual field value" do
    check all(
            suggestions <- list_of(suggestion_generator(), min_length: 0, max_length: 10),
            contact <- contact_generator()
          ) do
      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      for suggestion <- result do
        contact_key = Map.get(@field_to_contact_key, suggestion.field)
        expected_current = if contact_key, do: Map.get(contact, contact_key), else: nil
        assert suggestion.current_value == expected_current
      end
    end
  end

  property "all returned suggestions have has_change set to true" do
    check all(
            suggestions <- list_of(suggestion_generator(), min_length: 0, max_length: 10),
            contact <- contact_generator()
          ) do
      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      for suggestion <- result do
        assert suggestion.has_change == true
      end
    end
  end

  property "all returned suggestions have apply set to true" do
    check all(
            suggestions <- list_of(suggestion_generator(), min_length: 0, max_length: 10),
            contact <- contact_generator()
          ) do
      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      for suggestion <- result do
        assert suggestion.apply == true
      end
    end
  end

  property "output length is always <= input length" do
    check all(
            suggestions <- list_of(suggestion_generator(), min_length: 0, max_length: 10),
            contact <- contact_generator()
          ) do
      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)
      assert length(result) <= length(suggestions)
    end
  end

  property "empty suggestions returns empty list" do
    check all(contact <- contact_generator()) do
      assert SalesforceSuggestions.merge_with_contact([], contact) == []
    end
  end
end
