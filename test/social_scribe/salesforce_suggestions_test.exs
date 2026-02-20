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

    defp setup_mox do
      Mox.verify_on_exit!()
    end
  end
end
