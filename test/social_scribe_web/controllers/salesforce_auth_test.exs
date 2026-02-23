defmodule SocialScribeWeb.SalesforceAuthTest do
  use SocialScribeWeb.ConnCase

  setup :register_and_log_in_user

  describe "Salesforce OAuth callback" do
    test "creates credential on successful auth", %{conn: conn, user: user} do
      auth = %Ueberauth.Auth{
        uid: "00Dxx0000001gER_005xx0000001abc",
        provider: :salesforce,
        credentials: %Ueberauth.Auth.Credentials{
          token: "sf_access_token",
          refresh_token: "sf_refresh_token",
          token_type: "Bearer",
          expires: true,
          expires_at: nil,
          other: %{instance_url: "https://na1.salesforce.com", issued_at: "1234567890000"}
        },
        info: %Ueberauth.Auth.Info{
          email: "advisor@example.com",
          name: "Test Advisor"
        }
      }

      # Bypass Ueberauth plug and call controller directly
      conn =
        conn
        |> bypass_through(SocialScribeWeb.Router, [:browser])
        |> get("/")
        |> assign(:ueberauth_auth, auth)
        |> assign(:current_user, user)

      conn =
        SocialScribeWeb.AuthController.callback(conn, %{"provider" => "salesforce"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Salesforce"

      credential = SocialScribe.Accounts.get_user_salesforce_credential(user.id)
      assert credential.provider == "salesforce"
      assert credential.uid == "00Dxx0000001gER_005xx0000001abc"
      assert credential.token == "sf_access_token"
      assert credential.refresh_token == "sf_refresh_token"
      assert credential.instance_url == "https://na1.salesforce.com"
      assert credential.email == "advisor@example.com"
    end

    test "shows error when instance_url is missing", %{conn: conn, user: user} do
      auth = %Ueberauth.Auth{
        uid: "00Dxx0000001gER_005xx0000001abc",
        provider: :salesforce,
        credentials: %Ueberauth.Auth.Credentials{
          token: "sf_access_token",
          refresh_token: "sf_refresh_token",
          token_type: "Bearer",
          expires: true,
          expires_at: nil,
          other: %{instance_url: nil}
        },
        info: %Ueberauth.Auth.Info{
          email: "advisor@example.com",
          name: "Test Advisor"
        }
      }

      conn =
        conn
        |> bypass_through(SocialScribeWeb.Router, [:browser])
        |> get("/")
        |> assign(:ueberauth_auth, auth)
        |> assign(:current_user, user)

      conn =
        SocialScribeWeb.AuthController.callback(conn, %{"provider" => "salesforce"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "instance URL"

      # No credential should be created
      assert SocialScribe.Accounts.get_user_salesforce_credential(user.id) == nil
    end

    test "rejects instance_url with non-Salesforce domain (SSRF prevention)", %{
      conn: conn,
      user: user
    } do
      auth = %Ueberauth.Auth{
        uid: "00Dxx0000001gER_005xx0000001abc",
        provider: :salesforce,
        credentials: %Ueberauth.Auth.Credentials{
          token: "sf_access_token",
          refresh_token: "sf_refresh_token",
          token_type: "Bearer",
          expires: true,
          expires_at: nil,
          other: %{instance_url: "https://evil-attacker.com"}
        },
        info: %Ueberauth.Auth.Info{
          email: "advisor@example.com",
          name: "Test Advisor"
        }
      }

      conn =
        conn
        |> bypass_through(SocialScribeWeb.Router, [:browser])
        |> get("/")
        |> assign(:ueberauth_auth, auth)
        |> assign(:current_user, user)

      conn =
        SocialScribeWeb.AuthController.callback(conn, %{"provider" => "salesforce"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid instance URL domain"

      # No credential should be created
      assert SocialScribe.Accounts.get_user_salesforce_credential(user.id) == nil
    end
  end
end
