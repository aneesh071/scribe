defmodule SocialScribeWeb.LiveHooks do
  @moduledoc """
  LiveView lifecycle hooks for the application.

  Provides the `:assign_current_path` on_mount hook that tracks the current
  URI path in socket assigns for sidebar active-state detection.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:assign_current_path, _params, _session, socket) do
    socket =
      attach_hook(socket, :assign_current_path, :handle_params, &assign_current_path/3)

    {:cont, socket}
  end

  defp assign_current_path(_params, uri, socket) do
    uri = URI.parse(uri)

    {:cont, assign(socket, :current_path, uri.path)}
  end
end
