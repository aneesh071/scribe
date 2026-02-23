defmodule SocialScribeWeb.ModalComponents do
  @moduledoc """
  Reusable UI components for CRM integration modals.

  Shared between HubSpot and Salesforce modals. All components accept a
  `theme` attribute ("hubspot" or "salesforce") that switches color palettes
  via Tailwind utility classes.

  ## Components

  - `crm_modal` - Themed modal wrapper with overlay and close button
  - `contact_select` - Searchable contact dropdown with avatar and company display
  - `suggestion_card` - Individual field update suggestion with checkbox and value comparison
  - `suggestion_group` - Collapsible group of suggestion cards by category
  - `avatar` - Initials-based avatar circle
  - `modal_footer` - Cancel/submit button bar with field count
  - `empty_state` - Empty state message display
  - `inline_error` - Error message display
  """
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  import SocialScribeWeb.CoreComponents, only: [icon: 1]

  defp theme_class(theme, token) do
    "#{theme}-#{token}"
  end

  @doc """
  Renders a searchable contact select box.

  Shows selected contact with avatar, or search input when no contact selected.
  Auto-searches when typing, dropdown shows results.

  ## Examples

      <.contact_select
        selected_contact={@selected_contact}
        contacts={@contacts}
        loading={@loading}
        open={@dropdown_open}
        query={@query}
        target={@myself}
      />
  """
  attr :selected_contact, :map, default: nil
  attr :contacts, :list, default: []
  attr :loading, :boolean, default: false
  attr :open, :boolean, default: false
  attr :query, :string, default: ""
  attr :target, :any, default: nil
  attr :error, :string, default: nil
  attr :id, :string, default: "contact-select"
  attr :theme, :string, default: "hubspot"

  def contact_select(assigns) do
    ~H"""
    <div class="space-y-1">
      <label for={"#{@id}-input"} class="block text-sm font-medium text-slate-700">
        Select Contact
      </label>
      <div class="relative">
        <%= if @selected_contact do %>
          <button
            type="button"
            phx-click="toggle_contact_dropdown"
            phx-target={@target}
            role="combobox"
            aria-haspopup="listbox"
            aria-expanded={to_string(@open)}
            aria-controls={"#{@id}-listbox"}
            class={"relative w-full bg-white border border-#{theme_class(@theme, "input")} rounded-lg pl-1.5 pr-10 py-[5px] text-left cursor-pointer focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm"}
          >
            <span class="flex items-center">
              <.avatar
                firstname={@selected_contact.firstname}
                lastname={@selected_contact.lastname}
                size={:sm}
                theme={@theme}
              />
              <span class="ml-1.5 block truncate text-slate-900">
                {@selected_contact.firstname} {@selected_contact.lastname}
              </span>
            </span>
            <span class="absolute inset-y-0 right-0 flex items-center pr-2 pointer-events-none">
              <.icon
                name="hero-chevron-up-down"
                class={"h-5 w-5 text-#{theme_class(@theme, "icon")}"}
              />
            </span>
          </button>
        <% else %>
          <div class="relative">
            <input
              id={"#{@id}-input"}
              type="text"
              name="contact_query"
              value={@query}
              placeholder="Search contacts..."
              phx-keyup="contact_search"
              phx-target={@target}
              phx-focus="open_contact_dropdown"
              phx-debounce="150"
              autocomplete="off"
              role="combobox"
              aria-autocomplete="list"
              aria-expanded={to_string(@open)}
              aria-controls={"#{@id}-listbox"}
              class={"w-full bg-white border border-#{theme_class(@theme, "input")} rounded-lg pl-2 pr-10 py-[5px] text-left focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm"}
            />
            <span class="absolute inset-y-0 right-0 flex items-center pr-2 pointer-events-none">
              <%= if @loading do %>
                <.icon
                  name="hero-arrow-path"
                  class={"h-5 w-5 text-#{theme_class(@theme, "icon")} animate-spin"}
                />
              <% else %>
                <.icon
                  name="hero-chevron-up-down"
                  class={"h-5 w-5 text-#{theme_class(@theme, "icon")}"}
                />
              <% end %>
            </span>
          </div>
        <% end %>

        <div
          :if={@open && (@selected_contact || Enum.any?(@contacts) || @loading || @query != "")}
          id={"#{@id}-listbox"}
          role="listbox"
          phx-click-away="close_contact_dropdown"
          phx-target={@target}
          class="absolute z-10 mt-1 w-full bg-white shadow-lg max-h-60 rounded-md py-1 text-base ring-1 ring-black ring-opacity-5 overflow-auto focus:outline-none sm:text-sm"
        >
          <button
            :if={@selected_contact}
            type="button"
            phx-click="clear_contact"
            phx-target={@target}
            role="option"
            aria-selected="false"
            class="w-full text-left px-4 py-2 hover:bg-slate-50 text-sm text-slate-700 cursor-pointer"
          >
            Clear selection
          </button>
          <div :if={@loading} class="px-4 py-2 text-sm text-gray-500">
            Searching...
          </div>
          <div
            :if={!@loading && Enum.empty?(@contacts) && @query != ""}
            class="px-4 py-2 text-sm text-gray-500"
          >
            No contacts found
          </div>
          <button
            :for={contact <- @contacts}
            type="button"
            phx-click="select_contact"
            phx-value-id={contact.id}
            phx-target={@target}
            role="option"
            aria-selected="false"
            class="w-full text-left px-4 py-2 hover:bg-slate-50 flex items-center space-x-3 cursor-pointer"
          >
            <.avatar
              firstname={contact.firstname}
              lastname={contact.lastname}
              size={:sm}
              theme={@theme}
            />
            <div>
              <div class="text-sm font-medium text-slate-900">
                {contact.firstname} {contact.lastname}
              </div>
              <div class="text-xs text-slate-500">
                {contact.email}
              </div>
            </div>
          </button>
        </div>
      </div>
      <.inline_error :if={@error} message={@error} />
    </div>
    """
  end

  @doc """
  Renders an avatar with initials.

  ## Examples

      <.avatar firstname="John" lastname="Doe" size={:md} />
  """
  attr :firstname, :string, default: ""
  attr :lastname, :string, default: ""
  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :class, :string, default: nil
  attr :theme, :string, default: "hubspot"

  def avatar(assigns) do
    size_classes = %{
      sm: "h-6 w-6 text-[10px]",
      md: "h-8 w-8 text-[10px]",
      lg: "h-10 w-10 text-sm"
    }

    assigns = assign(assigns, :size_class, size_classes[assigns.size])

    ~H"""
    <div class={[
      "rounded-full flex items-center justify-center font-semibold flex-shrink-0",
      "bg-#{theme_class(@theme, "avatar")}",
      "text-#{theme_class(@theme, "avatar-text")}",
      @size_class,
      @class
    ]}>
      {String.at(@firstname || "", 0)}{String.at(@lastname || "", 0)}
    </div>
    """
  end

  @doc """
  Renders a suggestion card with checkbox.

  ## Examples

      <.suggestion_card suggestion={%{field: "email", label: "Email", ...}} />
  """
  attr :suggestion, :map, required: true
  attr :class, :string, default: nil
  attr :theme, :string, default: "hubspot"

  def suggestion_card(assigns) do
    ~H"""
    <div class={["rounded-2xl p-6 mb-4", "bg-#{theme_class(@theme, "card")}", @class]}>
      <div class="flex items-start justify-between">
        <div class="flex items-start gap-3">
          <div class="flex items-center h-5 pt-0.5">
            <input
              type="checkbox"
              checked={@suggestion.apply}
              phx-click={JS.dispatch("click", to: "#suggestion-apply-#{@suggestion.field}")}
              class={"h-4 w-4 rounded-[3px] border-slate-300 text-#{theme_class(@theme, "checkbox")} accent-#{theme_class(@theme, "checkbox")} focus:ring-0 focus:ring-offset-0 cursor-pointer"}
            />
          </div>
          <div class="text-sm font-semibold text-slate-900 leading-5">{@suggestion.label}</div>
        </div>
      </div>

      <div class="mt-2 pl-8">
        <div class="text-sm font-medium text-slate-700 leading-5 ml-1">{@suggestion.label}</div>

        <div class="relative mt-2">
          <input
            id={"suggestion-apply-#{@suggestion.field}"}
            type="checkbox"
            name={"apply[#{@suggestion.field}]"}
            value="1"
            checked={@suggestion.apply}
            class={"absolute -left-8 top-1/2 -translate-y-1/2 h-4 w-4 rounded-[3px] border-slate-300 text-#{theme_class(@theme, "checkbox")} accent-#{theme_class(@theme, "checkbox")} focus:ring-0 focus:ring-offset-0 cursor-pointer"}
          />

          <div class="grid grid-cols-[1fr_32px_1fr] items-center gap-6">
            <input
              type="text"
              readonly
              value={@suggestion.current_value || ""}
              placeholder="No existing value"
              class={[
                "block w-full shadow-sm text-sm bg-white border border-gray-300 rounded-[7px] py-1.5 px-2",
                if(@suggestion.current_value && @suggestion.current_value != "",
                  do: "line-through text-gray-500",
                  else: "text-gray-400"
                )
              ]}
            />

            <div class={"w-8 flex justify-center text-#{theme_class(@theme, "arrow")}"}>
              <.icon name="hero-arrow-long-right" class="h-7 w-7" />
            </div>

            <input
              type="text"
              name={"values[#{@suggestion.field}]"}
              value={@suggestion.new_value}
              class={"block w-full shadow-sm text-sm text-slate-900 bg-white border border-#{theme_class(@theme, "input")} rounded-[7px] py-1.5 px-2 focus:ring-blue-500 focus:border-blue-500"}
            />
          </div>
        </div>

        <div :if={@suggestion[:timestamp]} class="mt-3">
          <span class="text-xs text-slate-500">
            Found in transcript<span
              class={"text-#{theme_class(@theme, "link")} hover:underline cursor-help"}
              title={@suggestion[:context]}
            >
              ({@suggestion[:timestamp]})
            </span>
          </span>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders a collapsible group of suggestion cards with a group-level checkbox.

  ## Examples

      <.suggestion_group name="Contact Info" suggestions={@group_suggestions} expanded={true} />
  """
  attr :name, :string, required: true
  attr :suggestions, :list, required: true
  attr :theme, :string, default: "hubspot"
  attr :expanded, :boolean, default: true
  attr :target, :any, default: nil

  def suggestion_group(assigns) do
    assigns =
      assign(
        assigns,
        :selected_count,
        Enum.count(assigns.suggestions, fn s -> s.apply == true end)
      )

    ~H"""
    <div class={"rounded-lg border border-#{theme_class(@theme, "input")} overflow-hidden"}>
      <div class="flex items-center justify-between px-4 py-3">
        <div class="flex items-center gap-3">
          <input
            type="checkbox"
            checked={@selected_count > 0}
            class={"h-4 w-4 rounded accent-#{theme_class(@theme, "checkbox")}"}
            phx-click="toggle_group"
            phx-value-group={@name}
            phx-target={@target}
          />
          <span class="font-medium text-sm text-slate-900">{@name}</span>
        </div>
        <div class="flex items-center gap-3">
          <span class={[
            "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
            "bg-#{theme_class(@theme, "pill")}",
            "text-#{theme_class(@theme, "pill-text")}"
          ]}>
            {@selected_count} update{if @selected_count != 1, do: "s"} selected
          </span>
          <button
            type="button"
            phx-click="toggle_group_expand"
            phx-value-group={@name}
            phx-target={@target}
            class={"text-sm text-#{theme_class(@theme, "hide")} hover:text-#{theme_class(@theme, "hide-hover")}"}
          >
            {if @expanded, do: "Hide details", else: "Show details"}
          </button>
        </div>
      </div>

      <div :if={@expanded} class="border-t border-dashed border-slate-200 px-4 py-3 space-y-4">
        <.suggestion_card :for={suggestion <- @suggestions} suggestion={suggestion} theme={@theme} />
      </div>
    </div>
    """
  end

  @doc """
  Renders a modal footer with cancel and submit buttons.

  ## Examples

      <.modal_footer
        cancel_url={~p"/dashboard"}
        submit_text="Save"
        loading={false}
      />
  """
  attr :cancel_patch, :string, default: nil
  attr :cancel_click, :any, default: nil
  attr :submit_text, :string, default: "Submit"
  attr :submit_class, :string, default: "bg-green-600 hover:bg-green-700"
  attr :loading, :boolean, default: false
  attr :disabled, :boolean, default: false
  attr :loading_text, :string, default: "Processing..."
  attr :info_text, :string, default: nil
  attr :class, :string, default: nil
  attr :theme, :string, default: "hubspot"

  def modal_footer(assigns) do
    ~H"""
    <div class={["relative pt-6 mt-6 flex items-center justify-between -mx-10 px-10", @class]}>
      <div class="absolute left-0 right-0 top-0 border-t border-slate-200"></div>
      <div :if={@info_text} class="text-xs text-slate-500">
        {@info_text}
      </div>
      <div :if={!@info_text}></div>
      <div class="flex space-x-3">
        <button
          :if={@cancel_patch}
          type="button"
          phx-click={Phoenix.LiveView.JS.patch(@cancel_patch)}
          class={"px-5 py-2.5 border border-slate-300 rounded-lg shadow-sm text-sm font-medium text-#{theme_class(@theme, "cancel")} bg-white hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"}
        >
          Cancel
        </button>
        <button
          :if={@cancel_click}
          type="button"
          phx-click={@cancel_click}
          class={"px-5 py-2.5 border border-slate-300 rounded-lg shadow-sm text-sm font-medium text-#{theme_class(@theme, "cancel")} bg-white hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"}
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={@loading || @disabled}
          class={
            "px-5 py-2.5 rounded-lg shadow-sm text-sm font-medium text-white " <>
              @submit_class <> " disabled:opacity-50"
          }
        >
          <span :if={@loading}>{@loading_text}</span>
          <span :if={!@loading}>{@submit_text}</span>
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders an empty state message.

  ## Examples

      <.empty_state title="No results" message="Try a different search." />
  """
  attr :title, :string, default: nil
  attr :message, :string, required: true
  attr :submessage, :string, default: nil
  attr :class, :string, default: nil

  def empty_state(assigns) do
    ~H"""
    <div class={["text-center py-8 text-slate-500", @class]}>
      <p :if={@title} class="font-medium text-slate-700 mb-1">{@title}</p>
      <p>{@message}</p>
      <p :if={@submessage} class="text-sm mt-2">{@submessage}</p>
    </div>
    """
  end

  @doc """
  Renders an error message.

  ## Examples

      <.inline_error :if={@error} message={@error} />
  """
  attr :message, :string, required: true
  attr :class, :string, default: nil

  def inline_error(assigns) do
    ~H"""
    <p class={["text-red-600 text-sm", @class]}>{@message}</p>
    """
  end

  @doc """
  Renders a CRM-styled modal wrapper.

  Uses the `theme` attr to apply CRM-specific overlay color (hubspot or salesforce).
  - Custom overlay color based on theme
  - Reduced padding
  - No close button (relies on Cancel button in footer)

  ## Examples

      <.crm_modal id="crm-modal" theme="hubspot" show on_cancel={JS.patch(~p"/back")}>
        Modal content here
      </.crm_modal>
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :theme, :string, required: true, values: ["hubspot", "salesforce"]
  slot :inner_block, required: true

  def crm_modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div
        id={"#{@id}-bg"}
        class={"bg-#{@theme}-overlay/90 fixed inset-0 transition-opacity"}
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center">
          <div class="w-full max-w-3xl p-4 sm:p-6 lg:py-8">
            <.focus_wrap
              id={"#{@id}-container"}
              phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
              phx-key="escape"
              phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
              class="shadow-zinc-700/10 ring-zinc-700/10 relative hidden rounded-2xl bg-white px-10 py-7 shadow-lg ring-1 transition"
            >
              <div id={"#{@id}-content"}>
                {render_slot(@inner_block)}
              </div>
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      time: 300,
      transition: {"transition-all ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-container",
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-container")
  end

  defp hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      time: 200,
      transition: {"transition-all ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-container",
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end
end
