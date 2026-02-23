defmodule SocialScribeWeb.MeetingLive.Index do
  @moduledoc """
  LiveView listing all past meetings with attendees, timestamps, and platform logos.
  """

  use SocialScribeWeb, :live_view

  import SocialScribeWeb.PlatformLogo

  alias SocialScribe.Meetings

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Past Meetings", meetings: [])}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    meetings = Meetings.list_user_meetings(socket.assigns.current_user)
    {:noreply, assign(socket, :meetings, meetings)}
  end

  defp format_duration(nil), do: "N/A"

  defp format_duration(seconds) when is_integer(seconds) do
    minutes = div(seconds, 60)
    "#{minutes} min"
  end
end
