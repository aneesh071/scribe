defmodule SocialScribeWeb.HomeLive do
  @moduledoc """
  Dashboard LiveView showing upcoming calendar events with bot recording toggles.

  Initiates calendar sync on connection and displays events with Zoom/Meet links.
  """

  use SocialScribeWeb, :live_view

  alias SocialScribe.Calendar
  alias SocialScribe.CalendarSyncronizer
  alias SocialScribe.Bots

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: send(self(), :sync_calendars)
    {:ok, assign(socket, page_title: "Upcoming Meetings", events: [], loading: true)}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    events = Calendar.list_upcoming_events(socket.assigns.current_user)
    {:noreply, assign(socket, :events, events)}
  end

  @impl true
  def handle_event("toggle_record", %{"id" => event_id}, socket) do
    case Calendar.get_calendar_event(event_id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Calendar event not found.")}

      event ->
        case Calendar.update_calendar_event(event, %{record_meeting: not event.record_meeting}) do
          {:ok, updated_event} ->
            send(self(), {:schedule_bot, updated_event})

            updated_events =
              Enum.map(socket.assigns.events, fn e ->
                if e.id == updated_event.id, do: updated_event, else: e
              end)

            {:noreply, assign(socket, :events, updated_events)}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to update recording preference.")}
        end
    end
  end

  @impl true
  def handle_info({:schedule_bot, event}, socket) do
    socket =
      if event.record_meeting == true do
        case Bots.create_and_dispatch_bot(socket.assigns.current_user, event) do
          {:ok, _} ->
            socket

          {:error, reason} ->
            Logger.error("Failed to create bot: #{inspect(reason)}")

            put_flash(
              socket,
              :error,
              "Failed to schedule recording bot. Please check your Recall API configuration."
            )
        end
      else
        case Bots.cancel_and_delete_bot(event) do
          {:ok, _} ->
            socket

          {:error, reason} ->
            Logger.error("Failed to cancel bot: #{inspect(reason)}")
            socket
        end
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:sync_calendars, socket) do
    user = socket.assigns.current_user

    Task.Supervisor.async_nolink(SocialScribe.TaskSupervisor, fn ->
      CalendarSyncronizer.sync_events_for_user(user)
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info({ref, {:ok, :sync_complete}}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    events = Calendar.list_upcoming_events(socket.assigns.current_user)

    {:noreply, socket |> assign(:events, events) |> assign(:loading, false)}
  end

  @impl true
  def handle_info({ref, _result}, socket) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    Logger.warning("Calendar sync returned unexpected result")
    {:noreply, assign(socket, :loading, false)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
    Logger.warning("Calendar sync task failed")
    {:noreply, assign(socket, :loading, false)}
  end
end
