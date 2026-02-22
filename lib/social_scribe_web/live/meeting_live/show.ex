defmodule SocialScribeWeb.MeetingLive.Show do
  @moduledoc """
  LiveView for viewing a single meeting's details, transcript, AI-generated
  content, and CRM integration modals (HubSpot, Salesforce).
  """

  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo
  import SocialScribeWeb.ClipboardButton
  import SocialScribeWeb.ModalComponents, only: [crm_modal: 1]

  alias SocialScribe.Accounts
  alias SocialScribe.Automations
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.HubspotSuggestions
  alias SocialScribe.Meetings
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi
  alias SocialScribe.SalesforceSuggestions

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Meeting Details",
       meeting: nil,
       automation_results: [],
       user_has_automations: false,
       hubspot_credential: nil,
       salesforce_credential: nil,
       last_hubspot_contact: nil,
       last_salesforce_contact: nil,
       follow_up_email_form: to_form(%{"follow_up_email" => ""})
     )}
  end

  @impl true
  def handle_params(%{"id" => meeting_id} = params, _uri, socket) do
    case Meetings.get_meeting_with_details(meeting_id) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Meeting not found.")
         |> push_navigate(to: ~p"/dashboard/meetings")}

      meeting ->
        if meeting.calendar_event.user_id != socket.assigns.current_user.id do
          {:noreply,
           socket
           |> put_flash(:error, "You do not have permission to view this meeting.")
           |> push_navigate(to: ~p"/dashboard/meetings")}
        else
          user_id = socket.assigns.current_user.id

          socket =
            socket
            |> assign(:page_title, "Meeting Details: #{meeting.title}")
            |> assign(:meeting, meeting)
            |> assign(
              :automation_results,
              Automations.list_automation_results_for_meeting(meeting_id)
            )
            |> assign(
              :user_has_automations,
              Automations.list_active_user_automations(user_id) |> Enum.any?()
            )
            |> assign(:hubspot_credential, Accounts.get_user_hubspot_credential(user_id))
            |> assign(:salesforce_credential, Accounts.get_user_salesforce_credential(user_id))
            |> maybe_load_automation_result(params)

          {:noreply, socket}
        end
    end
  end

  defp maybe_load_automation_result(socket, %{"automation_result_id" => automation_result_id}) do
    with %{} = automation_result <- Automations.get_automation_result(automation_result_id),
         %{} = automation <- Automations.get_automation(automation_result.automation_id) do
      socket
      |> assign(:automation_result, automation_result)
      |> assign(:automation, automation)
    else
      nil ->
        put_flash(socket, :error, "Automation result not found.")
    end
  end

  defp maybe_load_automation_result(socket, _params), do: socket

  @impl true
  def handle_event("validate-follow-up-email", params, socket) do
    socket =
      socket
      |> assign(:follow_up_email_form, to_form(params))

    {:noreply, socket}
  end

  # --- HubSpot handle_info callbacks ---

  @impl true
  def handle_info({:hubspot_search, query, credential}, socket) do
    case HubspotApi.search_contacts(credential, query) do
      {:ok, contacts} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          contacts: contacts,
          searching: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: "Failed to search contacts: #{inspect(reason)}",
          searching: false
        )
    end

    {:noreply, socket}
  rescue
    e in DBConnection.ConnectionError ->
      Logger.error("DB connection lost during HubSpot search: #{Exception.message(e)}")

      send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
        id: "hubspot-modal",
        error: "Service temporarily unavailable. Please try again.",
        searching: false
      )

      {:noreply, socket}
  end

  @impl true
  def handle_info({:generate_suggestions, contact, meeting, _credential}, socket) do
    case HubspotSuggestions.generate_suggestions_from_meeting(meeting) do
      {:ok, suggestions} ->
        merged = HubspotSuggestions.merge_with_contact(suggestions, contact)

        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          step: :suggestions,
          suggestions: merged,
          loading: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: "Failed to generate suggestions: #{inspect(reason)}",
          loading: false
        )
    end

    {:noreply, assign(socket, :last_hubspot_contact, contact)}
  end

  @impl true
  def handle_info({:apply_hubspot_updates, updates, contact, credential}, socket) do
    case HubspotApi.update_contact(credential, contact.id, updates) do
      {:ok, _updated_contact} ->
        socket =
          socket
          |> put_flash(:info, "Successfully updated #{map_size(updates)} field(s) in HubSpot")
          |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

        {:noreply, socket}

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: "Failed to update contact: #{inspect(reason)}",
          loading: false
        )

        {:noreply, socket}
    end
  end

  # --- Salesforce handle_info callbacks ---

  @impl true
  def handle_info({:salesforce_search, query, credential}, socket) do
    case SalesforceApi.search_contacts(credential, query) do
      {:ok, contacts} ->
        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          contacts: contacts,
          searching: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          error: "Failed to search contacts: #{inspect(reason)}",
          searching: false
        )
    end

    {:noreply, socket}
  rescue
    e in DBConnection.ConnectionError ->
      Logger.error("DB connection lost during Salesforce search: #{Exception.message(e)}")

      send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
        id: "salesforce-modal",
        error: "Service temporarily unavailable. Please try again.",
        searching: false
      )

      {:noreply, socket}
  end

  @impl true
  def handle_info({:generate_salesforce_suggestions, contact, meeting, _credential}, socket) do
    case SalesforceSuggestions.generate_suggestions_from_meeting(meeting) do
      {:ok, suggestions} ->
        merged = SalesforceSuggestions.merge_with_contact(suggestions, contact)

        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          suggestions: merged,
          loading: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          error: "Failed to generate suggestions: #{inspect(reason)}",
          loading: false
        )
    end

    {:noreply, assign(socket, :last_salesforce_contact, contact)}
  end

  @impl true
  def handle_info({:apply_salesforce_updates, updates, contact, credential}, socket) do
    case SalesforceApi.update_contact(credential, contact.id, updates) do
      {:ok, _} ->
        socket =
          socket
          |> put_flash(
            :info,
            "Successfully updated #{map_size(updates)} field(s) in Salesforce"
          )
          |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

        {:noreply, socket}

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          error: "Failed to update contact: #{inspect(reason)}",
          loading: false
        )

        {:noreply, socket}
    end
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    remaining_seconds = rem(seconds, 60)

    cond do
      minutes > 0 && remaining_seconds > 0 -> "#{minutes} min #{remaining_seconds} sec"
      minutes > 0 -> "#{minutes} min"
      seconds > 0 -> "#{seconds} sec"
      true -> "Less than a second"
    end
  end

  attr :meeting_transcript, :map, required: true

  defp transcript_content(assigns) do
    has_transcript =
      assigns.meeting_transcript &&
        assigns.meeting_transcript.content &&
        Map.get(assigns.meeting_transcript.content, "data") &&
        Enum.any?(Map.get(assigns.meeting_transcript.content, "data"))

    assigns =
      assigns
      |> assign(:has_transcript, has_transcript)

    ~H"""
    <div class="bg-white shadow-xl rounded-lg p-6 md:p-8">
      <h2 class="text-2xl font-semibold mb-4 text-slate-700">
        Meeting Transcript
      </h2>
      <div class="prose prose-sm sm:prose max-w-none h-96 overflow-y-auto pr-2">
        <%= if @has_transcript do %>
          <div :for={segment <- @meeting_transcript.content["data"]} class="mb-3">
            <p>
              <span class="font-semibold text-indigo-600">
                {segment["speaker"] || "Unknown Speaker"}:
              </span>
              {Enum.map_join(segment["words"] || [], " ", & &1["text"])}
            </p>
          </div>
        <% else %>
          <p class="text-slate-500">
            Transcript not available for this meeting.
          </p>
        <% end %>
      </div>
    </div>
    """
  end
end
