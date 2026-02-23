defmodule SocialScribeWeb.AutomationLive.Index do
  @moduledoc """
  LiveView for listing and managing user-defined content automation templates.
  """

  use SocialScribeWeb, :live_view

  alias SocialScribe.Automations
  alias SocialScribe.Automations.Automation

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :automations, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case Automations.get_automation(id) do
      nil ->
        socket
        |> put_flash(:error, "Automation not found.")
        |> push_navigate(to: ~p"/dashboard/automations")

      automation ->
        socket
        |> assign(:page_title, "Edit Automation")
        |> assign(:automation, automation)
    end
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Automation")
    |> assign(:automation, %Automation{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Automations")
    |> assign(:automation, nil)
    |> assign(:automations, Automations.list_user_automations(socket.assigns.current_user.id))
  end

  @impl true
  def handle_info({SocialScribeWeb.AutomationLive.FormComponent, {:saved, automation}}, socket) do
    socket =
      socket
      |> assign(:automations, [
        automation | Enum.filter(socket.assigns.automations, fn a -> a.id != automation.id end)
      ])

    {:noreply, socket}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Automations.get_automation(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Automation not found.")}

      automation ->
        case Automations.delete_automation(automation) do
          {:ok, _} ->
            {:noreply,
             assign(
               socket,
               :automations,
               Enum.reject(socket.assigns.automations, fn a -> a.id == automation.id end)
             )}

          {:error, _changeset} ->
            {:noreply, put_flash(socket, :error, "Failed to delete automation.")}
        end
    end
  end

  @impl true
  def handle_event("toggle_automation", %{"id" => id}, socket) do
    case Automations.get_automation(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Automation not found.")}

      automation ->
        case Automations.update_automation(automation, %{is_active: !automation.is_active}) do
          {:ok, updated_automation} ->
            socket =
              socket
              |> assign(
                :automations,
                Enum.map(socket.assigns.automations, fn a ->
                  if a.id == updated_automation.id, do: updated_automation, else: a
                end)
              )

            {:noreply, socket}

          {:error, _changeset} ->
            {:noreply,
             put_flash(socket, :error, "You can only have one active automation per platform")}
        end
    end
  end
end
