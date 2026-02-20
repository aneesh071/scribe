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
  end
end
