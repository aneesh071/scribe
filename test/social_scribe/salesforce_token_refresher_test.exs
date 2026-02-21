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

    test "returns credential unchanged when token has 2 hours remaining" do
      credential =
        salesforce_credential_fixture(%{
          expires_at: DateTime.add(DateTime.utc_now(), 7200, :second)
        })

      assert {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert result.token == credential.token
    end

    test "returns credential unchanged when well above the 5-minute buffer" do
      # Buffer is 300 seconds (5 min). 310 seconds should safely NOT trigger refresh.
      credential =
        salesforce_credential_fixture(%{
          expires_at: DateTime.add(DateTime.utc_now(), 310, :second)
        })

      assert {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert result.token == credential.token
    end

    test "attempts refresh when token is expired" do
      # Token expired 1 hour ago — should trigger refresh attempt
      credential =
        salesforce_credential_fixture(%{
          expires_at: DateTime.add(DateTime.utc_now(), -3600, :second)
        })

      # Refresh will fail because Salesforce credentials are test fixtures,
      # but we verify the expired path is triggered (not silently passed through)
      result = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert {:error, _reason} = result
    end

    test "attempts refresh when token expires within the buffer window" do
      # Token expires in 60 seconds — within the 300-second buffer — should refresh
      credential =
        salesforce_credential_fixture(%{
          expires_at: DateTime.add(DateTime.utc_now(), 60, :second)
        })

      result = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert {:error, _reason} = result
    end

    test "attempts refresh when expires_at is nil" do
      # nil expires_at should be treated as expired
      credential = salesforce_credential_fixture(%{})
      credential = %{credential | expires_at: nil}

      result = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert {:error, _reason} = result
    end
  end
end
