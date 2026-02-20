defmodule SocialScribe.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.SalesforceTokenRefresher

  import SocialScribe.AccountsFixtures

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      credential =
        salesforce_credential_fixture(%{
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when token expires in more than 5 minutes" do
      credential =
        salesforce_credential_fixture(%{
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      assert {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert result.id == credential.id
    end
  end
end
