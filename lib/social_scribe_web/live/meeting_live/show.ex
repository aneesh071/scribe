defmodule SocialScribeWeb.MeetingLive.Show do
  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo
  import SocialScribeWeb.ClipboardButton
  import SocialScribeWeb.ModalComponents, only: [crm_modal: 1]

  alias SocialScribe.Meetings
  alias SocialScribe.Automations
  alias SocialScribe.Accounts
  alias SocialScribe.HubspotApiBehaviour, as: HubspotApi
  alias SocialScribe.HubspotSuggestions
  alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi
  alias SocialScribe.SalesforceSuggestions

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Meeting Details")
     |> assign(:meeting, nil)
     |> assign(:automation_results, [])
     |> assign(:user_has_automations, false)
     |> assign(:hubspot_credential, nil)
     |> assign(:salesforce_credential, nil)
     |> assign(:last_salesforce_contact, nil)
     |> assign(:last_hubspot_contact, nil)
     |> assign(:follow_up_email_form, to_form(%{"follow_up_email" => ""}))}
  end

  @impl true
  def handle_params(%{"id" => meeting_id} = params, _uri, socket) do
    meeting = Meetings.get_meeting_with_details(meeting_id)

    cond do
      is_nil(meeting) ->
        {:noreply,
         socket
         |> put_flash(:error, "Meeting not found.")
         |> redirect(to: ~p"/dashboard/meetings")}

      meeting.calendar_event.user_id != socket.assigns.current_user.id ->
        {:noreply,
         socket
         |> put_flash(:error, "You do not have permission to view this meeting.")
         |> redirect(to: ~p"/dashboard/meetings")}

      true ->
        user_has_automations =
          Automations.list_active_user_automations(socket.assigns.current_user.id)
          |> length()
          |> Kernel.>(0)

        automation_results = Automations.list_automation_results_for_meeting(meeting_id)

        hubspot_credential =
          Accounts.get_user_hubspot_credential(socket.assigns.current_user.id)

        salesforce_credential =
          Accounts.get_user_salesforce_credential(socket.assigns.current_user.id)

        socket =
          socket
          |> assign(:page_title, "Meeting Details: #{meeting.title}")
          |> assign(:meeting, meeting)
          |> assign(:automation_results, automation_results)
          |> assign(:user_has_automations, user_has_automations)
          |> assign(:hubspot_credential, hubspot_credential)
          |> assign(:salesforce_credential, salesforce_credential)

        socket = apply_automation_result(socket, params)

        {:noreply, socket}
    end
  end

  defp apply_automation_result(socket, %{"automation_result_id" => automation_result_id}) do
    automation_result = Automations.get_automation_result!(automation_result_id)

    if automation_result.meeting_id != socket.assigns.meeting.id do
      socket
      |> put_flash(:error, "You do not have permission to view this automation result.")
      |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")
    else
      automation = Automations.get_automation!(automation_result.automation_id)

      socket
      |> assign(:automation_result, automation_result)
      |> assign(:automation, automation)
    end
  end

  defp apply_automation_result(socket, _params) do
    socket
    |> assign(:automation_result, nil)
    |> assign(:automation, nil)
  end

  @impl true
  def handle_event("validate-follow-up-email", params, socket) do
    socket =
      socket
      |> assign(:follow_up_email_form, to_form(params))

    {:noreply, socket}
  end

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
          error: "Failed to search contacts. #{friendly_error_message(reason)}",
          searching: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:generate_suggestions, contact, meeting, _credential}, socket) do
    socket = assign(socket, :last_hubspot_contact, contact)

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
          error: "Failed to generate suggestions. #{friendly_error_message(reason)}",
          loading: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:apply_hubspot_updates, updates, contact, credential}, socket) do
    case HubspotApi.update_contact(credential, contact.id, updates) do
      {:ok, _updated_contact} ->
        socket =
          socket
          |> assign(:last_hubspot_contact, contact)
          |> put_flash(:info, "Successfully updated #{map_size(updates)} field(s) in HubSpot")
          |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

        {:noreply, socket}

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.HubspotModalComponent,
          id: "hubspot-modal",
          error: "Failed to update contact. #{friendly_error_message(reason)}",
          loading: false
        )

        {:noreply, socket}
    end
  end

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
          error: "Failed to search contacts. #{friendly_error_message(reason)}",
          searching: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:generate_salesforce_suggestions, contact, meeting, _credential}, socket) do
    socket = assign(socket, :last_salesforce_contact, contact)

    case SalesforceSuggestions.generate_suggestions_from_meeting(meeting) do
      {:ok, suggestions} ->
        merged = SalesforceSuggestions.merge_with_contact(suggestions, contact)

        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          step: :suggestions,
          suggestions: merged,
          loading: false
        )

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          error: "Failed to generate suggestions. #{friendly_error_message(reason)}",
          loading: false
        )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:apply_salesforce_updates, updates, contact, credential}, socket) do
    case SalesforceApi.update_contact(credential, contact.id, updates) do
      {:ok, _} ->
        socket =
          socket
          |> assign(:last_salesforce_contact, contact)
          |> put_flash(:info, "Successfully updated #{map_size(updates)} field(s) in Salesforce")
          |> push_patch(to: ~p"/dashboard/meetings/#{socket.assigns.meeting}")

        {:noreply, socket}

      {:error, reason} ->
        send_update(SocialScribeWeb.MeetingLive.SalesforceModalComponent,
          id: "salesforce-modal",
          error: "Failed to update contact. #{friendly_error_message(reason)}",
          loading: false
        )

        {:noreply, socket}
    end
  end

  defp friendly_error_message({:api_error, status, _body}) when status in [429, 503],
    do: "Service temporarily unavailable. Please try again in a moment."

  defp friendly_error_message({:api_error, 401, _body}),
    do: "Authentication expired. Please reconnect your account in Settings."

  defp friendly_error_message({:api_error, 400, _body}),
    do: "The request was invalid. Please check your data and try again."

  defp friendly_error_message({:api_error, status, _body}) when status >= 500,
    do: "The external service encountered an error. Please try again."

  defp friendly_error_message({:api_error, _status, _body}),
    do: "An unexpected error occurred. Please try again."

  defp friendly_error_message(:api_timeout),
    do: "The request timed out. Please try again."

  defp friendly_error_message(_reason),
    do: "An unexpected error occurred. Please try again."

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
