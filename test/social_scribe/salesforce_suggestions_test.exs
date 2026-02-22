defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.SalesforceSuggestions

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          category: "Contact Info",
          current_value: nil,
          new_value: "555-1234",
          context: "mentioned phone",
          timestamp: "02:35",
          apply: true,
          has_change: true
        },
        %{
          field: "Title",
          label: "Job Title",
          category: "Professional Details",
          current_value: nil,
          new_value: "VP Engineering",
          context: "mentioned title",
          timestamp: "03:10",
          apply: true,
          has_change: true
        }
      ]

      contact = %{
        id: "003xx",
        firstname: "John",
        lastname: "Smith",
        email: "john@example.com",
        phone: nil,
        jobtitle: "VP Engineering",
        company: "Acme Corp"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      # Title already matches — should be filtered out
      assert length(result) == 1
      assert hd(result).field == "Phone"
      assert hd(result).current_value == nil
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "Email",
          label: "Email",
          category: "Contact Info",
          current_value: nil,
          new_value: "john@example.com",
          context: "mentioned email",
          timestamp: "01:00",
          apply: true,
          has_change: true
        }
      ]

      contact = %{email: "john@example.com"}

      assert SalesforceSuggestions.merge_with_contact(suggestions, contact) == []
    end

    test "handles empty suggestions list" do
      assert SalesforceSuggestions.merge_with_contact([], %{}) == []
    end
  end

  describe "generate_suggestions_from_meeting/1" do
    test "transforms AI suggestions into structured format" do
      import Mox
      setup_mox()

      meeting = %{id: 1}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok,
         [
           %{field: "Phone", value: "555-9999", context: "gave phone number", timestamp: "02:30"},
           %{field: "Title", value: "CTO", context: "promoted to CTO", timestamp: "05:00"}
         ]}
      end)

      assert {:ok, suggestions} = SalesforceSuggestions.generate_suggestions_from_meeting(meeting)
      assert length(suggestions) == 2

      phone = Enum.find(suggestions, &(&1.field == "Phone"))
      assert phone.new_value == "555-9999"
      assert phone.label == "Phone"
      assert phone.category == "Contact Info"
      assert phone.apply == true
      assert phone.has_change == true
    end

    test "filters out AI-hallucinated field names not in the allowlist" do
      import Mox
      setup_mox()

      meeting = %{id: 1}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok,
         [
           %{field: "Phone", value: "555-9999", context: "gave phone number", timestamp: "02:30"},
           %{
             field: "Birthday",
             value: "1990-01-01",
             context: "mentioned birthday",
             timestamp: "03:00"
           },
           %{
             field: "AnnualRevenue",
             value: "1000000",
             context: "discussed revenue",
             timestamp: "04:00"
           },
           %{field: "Title", value: "CTO", context: "promoted to CTO", timestamp: "05:00"}
         ]}
      end)

      assert {:ok, suggestions} = SalesforceSuggestions.generate_suggestions_from_meeting(meeting)

      # Only Phone and Title are in the allowlist; Birthday and AnnualRevenue are not
      assert length(suggestions) == 2
      fields = Enum.map(suggestions, & &1.field)
      assert "Phone" in fields
      assert "Title" in fields
      refute "Birthday" in fields
      refute "AnnualRevenue" in fields
    end

    defp setup_mox do
      Mox.verify_on_exit!()
    end
  end

  describe "field consistency" do
    test "every allowed_field key exists in Fields.field_mapping (reverse direction)" do
      allowed = SalesforceSuggestions.allowed_fields()
      field_mapping_keys = MapSet.new(Map.keys(SocialScribe.Salesforce.Fields.field_mapping()))

      extra_in_labels = MapSet.difference(allowed, field_mapping_keys)

      assert MapSet.size(extra_in_labels) == 0,
             "Keys in @field_labels not found in Fields.field_mapping/0: #{inspect(MapSet.to_list(extra_in_labels))}"
    end

    test "all Fields.field_mapping keys are accepted by @allowed_fields" do
      Mox.verify_on_exit!()

      field_mapping_keys = Map.keys(SocialScribe.Salesforce.Fields.field_mapping())

      ai_suggestions =
        Enum.map(field_mapping_keys, fn field ->
          %{field: field, value: "test_value", context: "test context", timestamp: "01:00"}
        end)

      Mox.expect(
        SocialScribe.AIContentGeneratorMock,
        :generate_salesforce_suggestions,
        fn _meeting -> {:ok, ai_suggestions} end
      )

      {:ok, suggestions} =
        SocialScribe.SalesforceSuggestions.generate_suggestions_from_meeting(%{})

      returned_fields = Enum.map(suggestions, & &1.field) |> MapSet.new()
      expected_fields = MapSet.new(field_mapping_keys)

      assert returned_fields == expected_fields,
             "Fields in SalesforceSuggestions don't match Fields.field_mapping/0. " <>
               "Missing: #{inspect(MapSet.difference(expected_fields, returned_fields))}. " <>
               "Extra: #{inspect(MapSet.difference(returned_fields, expected_fields))}"

      # Verify every suggestion has a non-nil label
      for suggestion <- suggestions do
        assert is_binary(suggestion.label) and suggestion.label != "",
               "Field #{suggestion.field} has empty or nil label in SalesforceSuggestions"
      end

      # Verify every suggestion has a non-nil category
      for suggestion <- suggestions do
        assert is_binary(suggestion.category) and suggestion.category != "",
               "Field #{suggestion.field} has empty or nil category in SalesforceSuggestions"
      end
    end
  end
end
