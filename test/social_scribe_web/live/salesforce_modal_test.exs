defmodule SocialScribeWeb.SalesforceModalTest do
  use SocialScribeWeb.ConnCase

  import Phoenix.LiveViewTest
  import Mox
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures

  setup :verify_on_exit!

  describe "Salesforce Modal - rendering" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "shows Salesforce section when credential exists", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")
      assert has_element?(view, "h2", "Salesforce Integration")
      assert has_element?(view, "a", "Update Salesforce Contact")
    end

    test "renders modal when navigating to salesforce route", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")
      assert has_element?(view, "#salesforce-modal-wrapper")
      assert has_element?(view, "h2", "Update in Salesforce")
    end

    test "displays contact search input", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")
      assert has_element?(view, "input[placeholder*='Search']")
    end

    test "shows search initially without suggestions form", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")
      assert has_element?(view, "input[phx-keyup='contact_search']")
      refute has_element?(view, "form[phx-submit='apply_updates']")
    end

    test "modal can be closed by navigating back", %{conn: conn, meeting: meeting} do
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")
      assert has_element?(view, "#salesforce-modal-wrapper")

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")
      refute has_element?(view, "#salesforce-modal-wrapper")
    end

    test "renders modal description text", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")
      assert html =~ "suggested updates to sync with your integrations"
    end

    test "uses salesforce theme for contact select", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")
      # The contact_select renders with theme="salesforce" which applies salesforce CSS classes
      assert html =~ "salesforce"
    end
  end

  describe "Salesforce Modal - without credential" do
    setup %{conn: conn} do
      user = user_fixture()
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting
      }
    end

    test "does not show Salesforce section when no credential", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")

      refute html =~ "Salesforce Integration"
      refute html =~ "Update Salesforce Contact"
    end

    test "does not render modal when no credential", %{conn: conn, meeting: meeting} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")
      refute html =~ "salesforce-modal-wrapper"
    end
  end

  describe "Salesforce Modal - contact search interaction" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "triggers search when typing 2+ characters", %{conn: conn, meeting: meeting} do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, query ->
        assert query == "Jo"

        {:ok,
         [
           %{
             id: "003xx",
             firstname: "John",
             lastname: "Doe",
             email: "john@test.com",
             display_name: "John Doe"
           }
         ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("#salesforce-modal-wrapper input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Jo"})

      # Allow async message processing
      :timer.sleep(100)
      html = render(view)
      assert html =~ "John Doe"
    end

    test "does not trigger search for single character", %{conn: conn, meeting: meeting} do
      # No mock expectation set — if search_contacts is called, Mox will fail
      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("#salesforce-modal-wrapper input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "J"})

      # Should not show any contacts
      refute render(view) =~ "John"
    end

    test "displays search error when API fails", %{conn: conn, meeting: meeting} do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, _query ->
        {:error, {:api_error, 500, "Internal error"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("#salesforce-modal-wrapper input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Test"})

      :timer.sleep(100)
      html = render(view)
      assert html =~ "Failed to search contacts"
    end

    test "shows multiple contacts in dropdown", %{conn: conn, meeting: meeting} do
      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, _query ->
        {:ok,
         [
           %{
             id: "001",
             firstname: "Alice",
             lastname: "Smith",
             email: "alice@test.com",
             display_name: "Alice Smith"
           },
           %{
             id: "002",
             firstname: "Bob",
             lastname: "Smith",
             email: "bob@test.com",
             display_name: "Bob Smith"
           }
         ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("#salesforce-modal-wrapper input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Smith"})

      :timer.sleep(100)
      html = render(view)
      assert html =~ "Alice Smith"
      assert html =~ "Bob Smith"
    end
  end

  describe "Salesforce Modal - suggestion generation" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "selecting contact triggers suggestion generation", %{conn: conn, meeting: meeting} do
      contacts = [
        %{
          id: "003xx",
          firstname: "Jane",
          lastname: "Smith",
          email: "jane@test.com",
          phone: "555-0000",
          display_name: "Jane Smith"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, contacts} end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok, [%{field: "Phone", value: "555-1234", context: "shared phone", timestamp: "01:00"}]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Search for contacts
      view
      |> element("#salesforce-modal-wrapper input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Jane"})

      :timer.sleep(100)

      # Select the contact — triggers async suggestion generation
      view
      |> element("[phx-click='select_contact'][phx-value-id='003xx']")
      |> render_click()

      :timer.sleep(100)

      # After generation completes, suggestions should be rendered
      html = render(view)
      assert html =~ "555-1234"
      assert html =~ "Contact Info"
    end

    test "shows empty state when no suggestions generated", %{conn: conn, meeting: meeting} do
      contacts = [
        %{
          id: "003xx",
          firstname: "Jane",
          lastname: "Smith",
          email: "jane@test.com",
          display_name: "Jane Smith"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, contacts} end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting -> {:ok, []} end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("#salesforce-modal-wrapper input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Jane"})

      :timer.sleep(100)

      view
      |> element("[phx-click='select_contact'][phx-value-id='003xx']")
      |> render_click()

      :timer.sleep(100)
      html = render(view)
      assert html =~ "No update suggestions found"
    end

    test "shows suggestion groups after generating suggestions", %{conn: conn, meeting: meeting} do
      contacts = [
        %{
          id: "003xx",
          firstname: "Jane",
          lastname: "Smith",
          email: "jane@test.com",
          phone: nil,
          display_name: "Jane Smith"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, contacts} end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok,
         [
           %{field: "Phone", value: "555-1234", context: "shared phone", timestamp: "02:30"},
           %{field: "Title", value: "CFO", context: "mentioned role", timestamp: "05:00"}
         ]}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("#salesforce-modal-wrapper input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Jane"})

      :timer.sleep(100)

      view
      |> element("[phx-click='select_contact'][phx-value-id='003xx']")
      |> render_click()

      :timer.sleep(100)
      html = render(view)

      # Should show category groups
      assert html =~ "Contact Info"
      assert html =~ "Professional Details"
      # Should show the suggestion values
      assert html =~ "555-1234"
      assert html =~ "CFO"
      # Should show apply form
      assert html =~ "Update Salesforce"
    end

    test "shows error when suggestion generation fails", %{conn: conn, meeting: meeting} do
      contacts = [
        %{
          id: "003xx",
          firstname: "Jane",
          lastname: "Smith",
          email: "jane@test.com",
          display_name: "Jane Smith"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, contacts} end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:error, :api_timeout}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("#salesforce-modal-wrapper input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Jane"})

      :timer.sleep(100)

      view
      |> element("[phx-click='select_contact'][phx-value-id='003xx']")
      |> render_click()

      :timer.sleep(100)
      html = render(view)
      assert html =~ "Failed to generate suggestions"
    end
  end

  describe "Salesforce Modal - apply updates" do
    setup %{conn: conn} do
      user = user_fixture()
      salesforce_credential = salesforce_credential_fixture(%{user_id: user.id})
      meeting = meeting_fixture_with_transcript(user)

      %{
        conn: log_in_user(conn, user),
        user: user,
        meeting: meeting,
        salesforce_credential: salesforce_credential
      }
    end

    test "successfully applies updates and shows flash", %{conn: conn, meeting: meeting} do
      contacts = [
        %{
          id: "003xx",
          firstname: "Jane",
          lastname: "Smith",
          email: "jane@test.com",
          phone: nil,
          display_name: "Jane Smith"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, contacts} end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok, [%{field: "Phone", value: "555-1234", context: "shared phone", timestamp: "02:30"}]}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:update_contact, fn _cred, "003xx", updates ->
        assert Map.has_key?(updates, "Phone")
        {:ok, :updated}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      # Search and select contact
      view
      |> element("#salesforce-modal-wrapper input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Jane"})

      :timer.sleep(100)

      view
      |> element("[phx-click='select_contact'][phx-value-id='003xx']")
      |> render_click()

      :timer.sleep(100)

      # Submit the form
      view
      |> element("form[phx-submit='apply_updates']")
      |> render_submit(%{
        "apply" => %{"Phone" => "1"},
        "values" => %{"Phone" => "555-1234"}
      })

      :timer.sleep(100)

      # Should redirect with flash
      flash = assert_patch(view)
      assert flash =~ "/dashboard/meetings/#{meeting.id}"
    end

    test "shows error when apply updates fails", %{conn: conn, meeting: meeting} do
      contacts = [
        %{
          id: "003xx",
          firstname: "Jane",
          lastname: "Smith",
          email: "jane@test.com",
          phone: nil,
          display_name: "Jane Smith"
        }
      ]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, _query -> {:ok, contacts} end)

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok, [%{field: "Phone", value: "555-1234"}]}
      end)

      SocialScribe.SalesforceApiMock
      |> expect(:update_contact, fn _cred, _id, _updates ->
        {:error, {:api_error, 400, "Bad request"}}
      end)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")

      view
      |> element("#salesforce-modal-wrapper input[phx-keyup='contact_search']")
      |> render_keyup(%{"value" => "Jane"})

      :timer.sleep(100)

      view
      |> element("[phx-click='select_contact'][phx-value-id='003xx']")
      |> render_click()

      :timer.sleep(100)

      view
      |> element("form[phx-submit='apply_updates']")
      |> render_submit(%{
        "apply" => %{"Phone" => "1"},
        "values" => %{"Phone" => "555-1234"}
      })

      :timer.sleep(100)
      html = render(view)
      assert html =~ "Failed to update contact"
    end
  end

  defp meeting_fixture_with_transcript(user) do
    meeting = meeting_fixture(%{})

    calendar_event = SocialScribe.Calendar.get_calendar_event!(meeting.calendar_event_id)

    {:ok, _updated_event} =
      SocialScribe.Calendar.update_calendar_event(calendar_event, %{user_id: user.id})

    meeting_transcript_fixture(%{
      meeting_id: meeting.id,
      content: %{
        "data" => [
          %{
            "speaker" => "Jane Smith",
            "words" => [
              %{"text" => "My"},
              %{"text" => "new"},
              %{"text" => "phone"},
              %{"text" => "number"},
              %{"text" => "is"},
              %{"text" => "555-9876"}
            ]
          }
        ]
      }
    })

    SocialScribe.Meetings.get_meeting_with_details(meeting.id)
  end
end
