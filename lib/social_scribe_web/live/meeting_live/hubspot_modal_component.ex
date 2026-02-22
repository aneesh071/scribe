defmodule SocialScribeWeb.MeetingLive.HubspotModalComponent do
  @moduledoc """
  LiveComponent for the HubSpot CRM integration modal.

  Provides contact search, AI-generated suggestion cards with category grouping,
  and selective field update submission. Communicates with the parent LiveView
  via send/send_update pattern for all async API operations.
  """
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ModalComponents

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :patch, ~p"/dashboard/meetings/#{assigns.meeting}")
    assigns = assign_new(assigns, :modal_id, fn -> "hubspot-modal-wrapper" end)

    ~H"""
    <div class="space-y-6">
      <div>
        <h2 id={"#{@modal_id}-title"} class="text-xl font-medium tracking-tight text-slate-900">
          Update in HubSpot
        </h2>
        <p id={"#{@modal_id}-description"} class="mt-2 text-base font-light leading-7 text-slate-500">
          Here are suggested updates to sync with your integrations based on this
          <span class="block">meeting</span>
        </p>
      </div>

      <.contact_select
        selected_contact={@selected_contact}
        contacts={@contacts}
        loading={@searching}
        open={@dropdown_open}
        query={@query}
        target={@myself}
        error={@error}
        theme="hubspot"
      />

      <%= if @selected_contact do %>
        <.suggestions_section
          suggestions={@suggestions}
          loading={@loading}
          myself={@myself}
          patch={@patch}
          expanded_groups={@expanded_groups}
        />
      <% end %>
    </div>
    """
  end

  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true
  attr :myself, :any, required: true
  attr :patch, :string, required: true
  attr :expanded_groups, :map, required: true

  defp suggestions_section(assigns) do
    assigns =
      assign(
        assigns,
        :selected_count,
        Enum.count(assigns.suggestions, fn s -> s.apply == true end)
      )

    category_order = [
      "Contact Info",
      "Professional Details",
      "Address",
      "Social & Web",
      "Other"
    ]

    assigns =
      assign(
        assigns,
        :grouped,
        assigns.suggestions
        |> Enum.group_by(& &1.category)
        |> Enum.sort_by(fn {cat, _} -> Enum.find_index(category_order, &(&1 == cat)) || 999 end)
      )

    ~H"""
    <div class="space-y-4">
      <%= if @loading do %>
        <div class="text-center py-8 text-slate-500">
          <.icon name="hero-arrow-path" class="h-6 w-6 animate-spin mx-auto mb-2" />
          <p>Generating suggestions...</p>
        </div>
      <% else %>
        <%= if Enum.empty?(@suggestions) do %>
          <.empty_state
            message="No update suggestions found from this meeting."
            submessage="The AI didn't detect any new contact information in the transcript."
          />
        <% else %>
          <form phx-submit="apply_updates" phx-change="toggle_suggestion" phx-target={@myself}>
            <div class="space-y-4 max-h-[60vh] overflow-y-auto pr-2">
              <.suggestion_group
                :for={{category, group_suggestions} <- @grouped}
                name={category}
                suggestions={group_suggestions}
                expanded={Map.get(@expanded_groups, category, true)}
                theme="hubspot"
                target={@myself}
              />
            </div>

            <.modal_footer
              cancel_patch={@patch}
              submit_text="Update HubSpot"
              submit_class="bg-hubspot-button hover:bg-hubspot-button-hover"
              disabled={@selected_count == 0}
              loading={@loading}
              loading_text="Updating..."
              info_text={"1 object, #{@selected_count} field#{if @selected_count != 1, do: "s"} in 1 integration selected to update"}
              theme="hubspot"
            />
          </form>
        <% end %>
      <% end %>
    </div>
    """
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> maybe_select_all_suggestions(assigns)
      |> assign_new(:step, fn -> :search end)
      |> assign_new(:query, fn -> "" end)
      |> assign_new(:contacts, fn -> [] end)
      |> assign_new(:selected_contact, fn -> nil end)
      |> assign_new(:suggestions, fn -> [] end)
      |> assign_new(:loading, fn -> false end)
      |> assign_new(:searching, fn -> false end)
      |> assign_new(:dropdown_open, fn -> false end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:expanded_groups, fn -> %{} end)
      |> maybe_restore_last_contact(assigns)

    {:ok, socket}
  end

  defp maybe_restore_last_contact(socket, %{last_contact: contact})
       when not is_nil(contact) and is_nil(socket.assigns.selected_contact) do
    socket = assign(socket, selected_contact: contact, loading: true)

    send(
      self(),
      {:generate_suggestions, contact, socket.assigns.meeting, socket.assigns.credential}
    )

    socket
  end

  defp maybe_restore_last_contact(socket, _assigns), do: socket

  defp maybe_select_all_suggestions(socket, %{suggestions: suggestions})
       when is_list(suggestions) do
    assign(socket, suggestions: Enum.map(suggestions, &Map.put(&1, :apply, true)))
  end

  defp maybe_select_all_suggestions(socket, _assigns), do: socket

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)

    if String.length(query) >= 2 do
      socket = assign(socket, searching: true, error: nil, query: query, dropdown_open: true)
      send(self(), {:hubspot_search, query, socket.assigns.credential})
      {:noreply, socket}
    else
      {:noreply, assign(socket, query: query, contacts: [], dropdown_open: query != "")}
    end
  end

  @impl true
  def handle_event("open_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: true)}
  end

  @impl true
  def handle_event("close_contact_dropdown", _params, socket) do
    {:noreply, assign(socket, dropdown_open: false)}
  end

  @impl true
  def handle_event("toggle_contact_dropdown", _params, socket) do
    if socket.assigns.dropdown_open do
      {:noreply, assign(socket, dropdown_open: false)}
    else
      socket = assign(socket, dropdown_open: true, searching: true)

      query =
        case socket.assigns.selected_contact do
          %{firstname: firstname, lastname: lastname} ->
            "#{firstname} #{lastname}"

          _ ->
            socket.assigns.query
        end

      send(self(), {:hubspot_search, query, socket.assigns.credential})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    contact = Enum.find(socket.assigns.contacts, &(&1.id == contact_id))

    if contact do
      socket =
        assign(socket,
          loading: true,
          selected_contact: contact,
          error: nil,
          dropdown_open: false,
          query: "",
          suggestions: []
        )

      send(
        self(),
        {:generate_suggestions, contact, socket.assigns.meeting, socket.assigns.credential}
      )

      {:noreply, socket}
    else
      {:noreply, assign(socket, error: "Contact not found")}
    end
  end

  @impl true
  def handle_event("clear_contact", _params, socket) do
    {:noreply,
     assign(socket,
       step: :search,
       selected_contact: nil,
       suggestions: [],
       loading: false,
       searching: false,
       dropdown_open: false,
       contacts: [],
       query: "",
       error: nil,
       expanded_groups: %{}
     )}
  end

  @impl true
  def handle_event("toggle_group", %{"group" => group_name}, socket) do
    group_suggestions =
      Enum.filter(socket.assigns.suggestions, &(&1.category == group_name))

    all_applied = Enum.all?(group_suggestions, fn s -> s.apply == true end)

    updated =
      Enum.map(socket.assigns.suggestions, fn s ->
        if s.category == group_name, do: %{s | apply: !all_applied}, else: s
      end)

    {:noreply, assign(socket, suggestions: updated)}
  end

  @impl true
  def handle_event("toggle_group_expand", %{"group" => group_name}, socket) do
    expanded = Map.update(socket.assigns.expanded_groups, group_name, false, &(!&1))
    {:noreply, assign(socket, expanded_groups: expanded)}
  end

  @impl true
  def handle_event("toggle_suggestion", params, socket) do
    applied_fields = Map.get(params, "apply", %{})
    values = Map.get(params, "values", %{})
    checked_fields = Map.keys(applied_fields)

    updated_suggestions =
      Enum.map(socket.assigns.suggestions, fn suggestion ->
        apply? = suggestion.field in checked_fields

        suggestion =
          case Map.get(values, suggestion.field) do
            nil -> suggestion
            new_value -> %{suggestion | new_value: new_value}
          end

        %{suggestion | apply: apply?}
      end)

    {:noreply, assign(socket, suggestions: updated_suggestions)}
  end

  @impl true
  def handle_event("apply_updates", %{"apply" => selected, "values" => values}, socket) do
    socket = assign(socket, loading: true, error: nil)

    updates =
      selected
      |> Map.keys()
      |> Enum.reduce(%{}, fn field, acc ->
        Map.put(acc, field, Map.get(values, field, ""))
      end)

    send(
      self(),
      {:apply_hubspot_updates, updates, socket.assigns.selected_contact,
       socket.assigns.credential}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_updates", _params, socket) do
    {:noreply, assign(socket, error: "Please select at least one field to update")}
  end
end
