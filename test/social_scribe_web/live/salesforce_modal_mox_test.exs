defmodule SocialScribeWeb.SalesforceModalMoxTest do
  use SocialScribeWeb.ConnCase

  import Mox
  import SocialScribe.AccountsFixtures

  setup :verify_on_exit!

  describe "behaviour delegation" do
    test "search_contacts delegates to implementation" do
      credential = salesforce_credential_fixture()
      expected = [%{id: "003xx", firstname: "John", lastname: "Doe", email: "john@test.com"}]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, query ->
        assert query == "test query"
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.search_contacts(credential, "test query")
    end

    test "get_contact delegates to implementation" do
      credential = salesforce_credential_fixture()
      expected = %{id: "003xx", firstname: "John", lastname: "Doe"}

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, id ->
        assert id == "003xx"
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.get_contact(credential, "003xx")
    end

    test "update_contact delegates to implementation" do
      credential = salesforce_credential_fixture()

      SocialScribe.SalesforceApiMock
      |> expect(:update_contact, fn _cred, id, updates ->
        assert id == "003xx"
        assert updates == %{"Phone" => "555-1234"}
        {:ok, :updated}
      end)

      assert {:ok, :updated} =
               SocialScribe.SalesforceApiBehaviour.update_contact(
                 credential,
                 "003xx",
                 %{"Phone" => "555-1234"}
               )
    end

    test "apply_updates delegates to implementation" do
      credential = salesforce_credential_fixture()

      SocialScribe.SalesforceApiMock
      |> expect(:apply_updates, fn _cred, contact_id, updates ->
        assert contact_id == "003xx"
        assert is_list(updates)
        {:ok, :updated}
      end)

      assert {:ok, :updated} =
               SocialScribe.SalesforceApiBehaviour.apply_updates(
                 credential,
                 "003xx",
                 [%{field: "Phone", new_value: "555-1234", apply: true}]
               )
    end
  end
end
