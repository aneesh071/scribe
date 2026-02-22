defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.SalesforceApi

  import SocialScribe.AccountsFixtures

  describe "format_contact/1" do
    test "normalizes Salesforce record to internal format" do
      record = %{
        "Id" => "003xx000004TMMa",
        "FirstName" => "John",
        "LastName" => "Smith",
        "Email" => "john@example.com",
        "Phone" => "555-1234",
        "MobilePhone" => nil,
        "Title" => "VP Engineering",
        "Department" => "Engineering",
        "MailingStreet" => "123 Main St",
        "MailingCity" => "San Francisco",
        "MailingState" => "CA",
        "MailingPostalCode" => "94105",
        "MailingCountry" => "US",
        "Account" => %{"Name" => "Acme Corp"}
      }

      contact = SalesforceApi.format_contact(record)

      assert contact.id == "003xx000004TMMa"
      # Must use :firstname/:lastname to match contact_select component
      assert contact.firstname == "John"
      assert contact.lastname == "Smith"
      assert contact.email == "john@example.com"
      assert contact.phone == "555-1234"
      assert contact.jobtitle == "VP Engineering"
      assert contact.company == "Acme Corp"
      assert contact.display_name == "John Smith"
    end

    test "handles missing Account gracefully" do
      record = %{
        "Id" => "003xx",
        "FirstName" => "Jane",
        "LastName" => "Doe",
        "Email" => "jane@example.com",
        "Phone" => nil,
        "MobilePhone" => nil,
        "Title" => nil,
        "Department" => nil,
        "MailingStreet" => nil,
        "MailingCity" => nil,
        "MailingState" => nil,
        "MailingPostalCode" => nil,
        "MailingCountry" => nil
      }

      contact = SalesforceApi.format_contact(record)
      assert contact.company == nil
      assert contact.display_name == "Jane Doe"
    end

    test "maps all mailing address fields correctly" do
      record = %{
        "Id" => "003xx",
        "FirstName" => "Test",
        "LastName" => "User",
        "Email" => nil,
        "Phone" => nil,
        "MobilePhone" => "555-0000",
        "Title" => nil,
        "Department" => nil,
        "MailingStreet" => "456 Oak Ave",
        "MailingCity" => "Portland",
        "MailingState" => "OR",
        "MailingPostalCode" => "97201",
        "MailingCountry" => "US"
      }

      contact = SalesforceApi.format_contact(record)
      assert contact.address == "456 Oak Ave"
      assert contact.city == "Portland"
      assert contact.state == "OR"
      assert contact.zip == "97201"
      assert contact.country == "US"
      assert contact.mobilephone == "555-0000"
    end

    test "builds display_name from first and last name" do
      record = %{"Id" => "1", "FirstName" => "Alice", "LastName" => "Wonder"}
      assert SalesforceApi.format_contact(record).display_name == "Alice Wonder"
    end

    test "uses only last name when first name is nil" do
      record = %{"Id" => "1", "FirstName" => nil, "LastName" => "Smith"}
      assert SalesforceApi.format_contact(record).display_name == "Smith"
    end

    test "uses only first name when last name is nil" do
      record = %{"Id" => "1", "FirstName" => "Jane", "LastName" => nil}
      assert SalesforceApi.format_contact(record).display_name == "Jane"
    end

    test "falls back to email when both names are nil" do
      record = %{
        "Id" => "1",
        "FirstName" => nil,
        "LastName" => nil,
        "Email" => "test@example.com"
      }

      assert SalesforceApi.format_contact(record).display_name == "test@example.com"
    end

    test "falls back to 'Unknown' when names and email are nil" do
      record = %{"Id" => "1", "FirstName" => nil, "LastName" => nil, "Email" => nil}
      assert SalesforceApi.format_contact(record).display_name == "Unknown"
    end

    test "handles Account with nil Name" do
      record = %{
        "Id" => "1",
        "FirstName" => "A",
        "LastName" => "B",
        "Account" => %{"Name" => nil}
      }

      assert SalesforceApi.format_contact(record).company == nil
    end

    test "handles Account as empty map" do
      record = %{"Id" => "1", "FirstName" => "A", "LastName" => "B", "Account" => %{}}
      assert SalesforceApi.format_contact(record).company == nil
    end
  end

  describe "apply_updates/3" do
    test "returns {:ok, :no_updates} when all updates have apply: false" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "Phone", new_value: "555-1234", apply: false},
        %{field: "Email", new_value: "new@test.com", apply: false}
      ]

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003xx", updates)
    end

    test "returns {:ok, :no_updates} when updates list is empty" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003xx", [])
    end

    test "returns {:ok, :no_updates} with mixed apply values where none are true" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "Phone", new_value: "555-1234", apply: false},
        %{field: "Email", new_value: "new@test.com", apply: nil},
        %{field: "Title", new_value: "CTO", apply: false}
      ]

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003xx", updates)
    end
  end

  describe "escape_soql_string/1" do
    test "escapes backslash" do
      assert SalesforceApi.escape_soql_string("test\\value") == "test\\\\value"
    end

    test "escapes single quote" do
      assert SalesforceApi.escape_soql_string("O'Brien") == "O\\'Brien"
    end

    test "escapes underscore wildcard" do
      assert SalesforceApi.escape_soql_string("test_name") == "test\\_name"
    end

    test "escapes percent wildcard" do
      assert SalesforceApi.escape_soql_string("100%") == "100\\%"
    end

    test "escapes multiple special characters" do
      assert SalesforceApi.escape_soql_string("O'Brien_100%\\done") ==
               "O\\'Brien\\_100\\%\\\\done"
    end

    test "returns empty string unchanged" do
      assert SalesforceApi.escape_soql_string("") == ""
    end

    test "returns string without special chars unchanged" do
      assert SalesforceApi.escape_soql_string("John Smith") == "John Smith"
    end

    test "escapes newline, carriage return, and tab" do
      assert SalesforceApi.escape_soql_string("line1\nline2") == "line1\\nline2"
      assert SalesforceApi.escape_soql_string("line1\rline2") == "line1\\rline2"
      assert SalesforceApi.escape_soql_string("col1\tcol2") == "col1\\tcol2"
    end
  end
end
