# Salesforce CRM Integration — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Salesforce CRM integration so financial advisors can search Salesforce contacts after meetings, review AI-generated field update suggestions, and sync changes to Salesforce — all following the established HubSpot pattern.

**Architecture:** Option C from brainstorming — build Salesforce as a parallel track to HubSpot with separate modules. Salesforce and HubSpot APIs are structurally different (SOQL vs JSON filters, PascalCase vs flatcase, dynamic instance_url vs fixed base URL, 200/204 vs JSON response on update), so no shared CRM abstraction. Reuse existing ModalComponents for UI (parameterized with theme prop for multi-CRM theming). Follow the established behaviour+facade+Mox pattern. Apply "make the change easy, then make the easy change" — Phase 3 refactors shared components before Phase 4+ adds Salesforce code.

**Tech Stack:** Elixir 1.17+, Phoenix 1.7 (LiveView), Ueberauth OAuth2, Tesla HTTP, Oban background jobs, Mox + StreamData testing, PostgreSQL, Tailwind CSS.

**Plan Structure:** 9 phases, 16 tasks. Phase 3 ("Make the Change Easy") prepares shared components for multi-CRM support before adding Salesforce-specific code.

---

### Revision Log (2026-02-21)

All Salesforce API assumptions verified against official documentation. Key fixes applied:

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | Critical | OAuth missing `redirect_uri`, `with_state_param`, `Ueberauth.json_library()` | Fixed in Task 6: added `redirect_uri: callback_url(conn)`, `with_state_param(conn)`, replaced hardcoded `Jason` with `Ueberauth.json_library()` |
| 2 | Critical | Shared UI components hardcode `hubspot-*` CSS classes | Added Task 3: parameterize all ModalComponents with `theme` prop + Salesforce color palette + Tailwind safelist |
| 3 | Critical | No category grouping in suggestion cards (ref UI shows groups) | Added Task 4: `suggestion_group` component with expand/collapse, `@field_categories` map in SalesforceSuggestions |
| 4 | Critical | DB queries in `mount/3` (Phoenix anti-pattern — mount called twice) | Added Task 5: move credential loading to `handle_params/3`; Task 14 also loads credentials in handle_params |
| 5 | Critical | Wrong project path (`/Users/aneeshnp/Jump/scribe`) | Fixed to `/Users/aneeshnp/Documents/Jump/scribe` |
| 6 | Medium | Shared components need theming for multi-CRM | Addressed in Task 3 with theme prop parameterization |
| 7 | Medium | Non-functional "Hide details" and "Update mapping" buttons | Addressed in Task 4 with working expand/collapse; "Update mapping" retained as placeholder per original design |
| 8 | Medium | Test gaps (no auth controller tests) | Added auth controller test in Task 15 Step 0 |
| 9 | Medium | SOQL escaping only handles single quotes | Added `escape_soql_string/1` helper that escapes both `\` and `'` |
| 10 | Low | PATCH should handle both 200 and 204 | Fixed: `status in [200, 204]` match |
| 11 | Low | SalesforceApi doesn't pattern-match on `%UserCredential{}` | Fixed: all public functions now match `%UserCredential{} = credential` |
| 12 | Low | Refresh token rotation not handled | Added `maybe_put_refresh_token/2` for defensive rotation handling |
| 13 | Low | "1 update selected" badge hardcoded | Fixed: dynamic count in `suggestion_group` and `modal_footer` `info_text` |
| 14 | Low | `normalize_contact/1` dead code in show.ex | Noted: will be addressed during cleanup (not in new code scope) |
| 15 | Low | Salesforce error codes in `is_token_error?` | SalesforceApi uses simpler 401-only check (adequate for Salesforce's `INVALID_SESSION_ID`) |
| 16 | Critical | SOQL `Name` is a compound field — may not be filterable via LIKE | Fixed: use `FirstName LIKE` + `LastName LIKE` instead of `Name LIKE` |
| 17 | Critical | SOQL escaping incomplete for LIKE clauses | Fixed: `escape_soql_string/1` now also escapes `_` and `%` (LIKE wildcards) |
| 18 | Critical | `fetch_user` fallback returns `"unknown"` user_id → invalid credential | Fixed: removed fallback, now errors if `id_url` is missing (Salesforce always provides it) |
| 19 | Medium | `get_user_info` uses hardcoded `Jason.decode!` | Fixed: now uses `Ueberauth.json_library().decode!(body)` for consistency |
| 20 | Low | Settings template uses `<h3>` but HubSpot uses `<h2>` | Fixed: changed to `<h2>` for consistency |

**API verification sources:** Salesforce OAuth2 docs, REST API Developer Guide, SOQL Reference, Contact Object Reference, community implementations on GitHub. **Second validation pass (2026-02-21):** 6 parallel agents validated all 16 tasks against the actual codebase — HubSpot reference patterns, schema/accounts, UI components, OAuth/config, AI/token refresh, and Salesforce API docs.

---

**Key Salesforce API Details (verified against official docs 2026-02-21):**
- OAuth: `login.salesforce.com/services/oauth2/{authorize,token}`, scope `api refresh_token`
- Token response includes `instance_url` (required for ALL subsequent API calls), `issued_at` (milliseconds, as string), `id` (identity URL) but NO `expires_in` — assume 2hr session (configurable 15min-24hr per org)
- Refresh tokens are stable by default (no rotation); orgs with "Rotate Refresh Tokens" enabled (opt-in since Spring 2024) return a new token — handle defensively
- SOQL response: `{"totalSize": N, "done": true/false, "records": [...]}` with `attributes` sub-object per record
- Contact search: `GET {instance_url}/services/data/v62.0/query/?q=SOQL` (use `FirstName`/`LastName` LIKE, NOT compound `Name` field)
- Contact update: `PATCH {instance_url}/services/data/v62.0/sobjects/Contact/{id}` → 200 OK or 204 No Content (handle both)
- Error format: `[{"message": "...", "errorCode": "...", "fields": [...]}]` (except 401 which uses OAuth format `{"error": "...", "error_description": "..."}`)
- Field naming: PascalCase (`FirstName`, `LastName`, `Title`, `Email`, `Phone`, `MobilePhone`, `MailingStreet`, `MailingCity`, `MailingState`, `MailingPostalCode`, `MailingCountry`, `Department`)
- Relationship queries: `Account.Name` returns as nested `record["Account"]["Name"]` (not flat)

**Important pattern to follow (from existing codebase):**
- `show.ex` uses `alias SocialScribe.HubspotApiBehaviour, as: HubspotApi` — always call through the behaviour facade, not the implementation directly
- Suggestion flow: parent calls `generate_suggestions_from_meeting/1` then `merge_with_contact/2` separately (not `generate_suggestions/3`)
- `contact_select` component expects `:firstname` / `:lastname` atom keys — Salesforce `format_contact` MUST normalize to match
- AI prompt must use Salesforce PascalCase field names — add separate `generate_salesforce_suggestions` callback (don't rename existing HubSpot one)

---

## Phase 1: Database & Schema

### Task 1: Add `instance_url` to `user_credentials`

Salesforce requires a per-org `instance_url` that varies per customer (e.g., `https://na1.salesforce.com`). All Salesforce API calls use this as base URL.

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_instance_url_to_user_credentials.exs`
- Modify: `lib/social_scribe/accounts/user_credential.ex`
- Modify: `test/support/fixtures/accounts_fixtures.ex`

**Step 1: Generate migration**

Run: `cd /Users/aneeshnp/Documents/Jump/scribe && mix ecto.gen.migration add_instance_url_to_user_credentials`

**Step 2: Write migration**

```elixir
defmodule SocialScribe.Repo.Migrations.AddInstanceUrlToUserCredentials do
  use Ecto.Migration

  def change do
    alter table(:user_credentials) do
      add :instance_url, :string
    end
  end
end
```

**Step 3: Update UserCredential schema**

In `lib/social_scribe/accounts/user_credential.ex`:
- Add `field :instance_url, :string` to the schema block (after `field :email, :string`)
- Add `:instance_url` to the cast list in the changeset function

**Step 4: Add salesforce_credential_fixture**

In `test/support/fixtures/accounts_fixtures.ex`, add:

```elixir
@doc """
Generate a Salesforce credential.
"""
def salesforce_credential_fixture(attrs \\ %{}) do
  user_id = attrs[:user_id] || user_fixture().id

  {:ok, credential} =
    attrs
    |> Enum.into(%{
      user_id: user_id,
      expires_at: DateTime.add(DateTime.utc_now(), 7200, :second),
      provider: "salesforce",
      refresh_token: "salesforce_refresh_#{System.unique_integer([:positive])}",
      token: "salesforce_token_#{System.unique_integer([:positive])}",
      uid: "00Dxx0000001gEREAY_#{System.unique_integer([:positive])}",
      email: "advisor@example.com",
      instance_url: "https://na1.salesforce.com"
    })
    |> SocialScribe.Accounts.create_user_credential()

  credential
end
```

**Step 5: Run migration and verify**

Run: `mix ecto.migrate && mix test`
Expected: Migration succeeds, all existing tests pass.

**Step 6: Commit**

```bash
git add priv/repo/migrations/*instance_url* lib/social_scribe/accounts/user_credential.ex test/support/fixtures/accounts_fixtures.ex
git commit -m "feat: add instance_url to user_credentials for Salesforce support"
```

---

## Phase 2: Accounts Context

### Task 2: Salesforce credential functions

**Files:**
- Modify: `lib/social_scribe/accounts.ex`
- Modify: `test/social_scribe/accounts_test.exs`

**Step 1: Write failing tests**

Add to `test/social_scribe/accounts_test.exs`:

```elixir
describe "salesforce credentials" do
  test "get_user_salesforce_credential/1 returns credential for user" do
    user = user_fixture()
    credential = salesforce_credential_fixture(%{user_id: user.id})

    result = Accounts.get_user_salesforce_credential(user.id)
    assert result.id == credential.id
    assert result.provider == "salesforce"
    assert result.instance_url == "https://na1.salesforce.com"
  end

  test "get_user_salesforce_credential/1 returns nil when no credential" do
    user = user_fixture()
    assert Accounts.get_user_salesforce_credential(user.id) == nil
  end

  test "find_or_create_salesforce_credential/2 creates new credential" do
    user = user_fixture()

    attrs = %{
      provider: "salesforce",
      token: "sf_token",
      refresh_token: "sf_refresh",
      uid: "00Dxx0000001gEREAY",
      email: "advisor@salesforce.com",
      user_id: user.id,
      expires_at: DateTime.add(DateTime.utc_now(), 7200, :second),
      instance_url: "https://na1.salesforce.com"
    }

    assert {:ok, credential} = Accounts.find_or_create_salesforce_credential(user, attrs)
    assert credential.provider == "salesforce"
    assert credential.token == "sf_token"
    assert credential.instance_url == "https://na1.salesforce.com"
  end

  test "find_or_create_salesforce_credential/2 updates existing credential" do
    user = user_fixture()
    existing = salesforce_credential_fixture(%{user_id: user.id})

    attrs = %{
      provider: "salesforce",
      token: "new_sf_token",
      refresh_token: "new_sf_refresh",
      uid: existing.uid,
      email: "advisor@salesforce.com",
      user_id: user.id,
      expires_at: DateTime.add(DateTime.utc_now(), 7200, :second),
      instance_url: "https://na2.salesforce.com"
    }

    assert {:ok, credential} = Accounts.find_or_create_salesforce_credential(user, attrs)
    assert credential.id == existing.id
    assert credential.token == "new_sf_token"
    assert credential.instance_url == "https://na2.salesforce.com"
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/social_scribe/accounts_test.exs`
Expected: FAIL — functions don't exist

**Step 3: Implement**

Add to `lib/social_scribe/accounts.ex` (near the existing `get_user_hubspot_credential` and `find_or_create_hubspot_credential` functions):

```elixir
@doc """
Gets the Salesforce credential for a user.
"""
def get_user_salesforce_credential(user_id) do
  Repo.get_by(UserCredential, user_id: user_id, provider: "salesforce")
end

@doc """
Creates or updates a Salesforce credential for a user.
"""
def find_or_create_salesforce_credential(user, attrs) do
  case get_user_credential(user, "salesforce", attrs.uid) do
    nil ->
      create_user_credential(attrs)

    %UserCredential{} = credential ->
      update_user_credential(credential, attrs)
  end
end
```

**Step 4: Run tests**

Run: `mix test test/social_scribe/accounts_test.exs`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/social_scribe/accounts.ex test/social_scribe/accounts_test.exs
git commit -m "feat: add Salesforce credential context functions"
```

---

## Phase 3: "Make the Change Easy" — Refactor Shared Components

> "First make the change easy, then make the easy change." — Kent Beck
>
> Before adding Salesforce-specific code, refactor existing code to support multiple CRM providers cleanly.

### Task 3: Parameterize ModalComponents with theme support

The existing `ModalComponents` (`contact_select`, `suggestion_card`, `value_comparison`, `avatar`, `modal_footer`) all hardcode `hubspot-*` Tailwind classes. This means rendering them in a Salesforce context would show HubSpot branding.

**Files:**
- Modify: `lib/social_scribe_web/components/modal_components.ex`
- Modify: `assets/tailwind.config.js`
- Modify: `lib/social_scribe_web/live/meeting_live/hubspot_modal_component.ex` (pass theme prop)

**Step 1: Add Salesforce color palette to Tailwind**

In `assets/tailwind.config.js`, add alongside the existing `hubspot` palette:

```javascript
salesforce: {
  overlay: "#B1B1B1",
  card: "#f5f8fa",
  input: "#C9C9C9",
  icon: "#706E6B",
  checkbox: "#0070D2",
  pill: "#E1E5EA",
  "pill-text": "#121418",
  link: "#0070D2",
  "link-hover": "#005FB2",
  hide: "#706E6B",
  "hide-hover": "#565A5E",
  cancel: "#151515",
  button: "#0070D2",
  "button-hover": "#005FB2",
  arrow: "#BBBCBB",
  avatar: "#1B96FF",
  "avatar-text": "#FFFFFF",
},
```

**Step 2: Add `theme` attr to all shared components**

Add `attr :theme, :string, default: "hubspot"` to `contact_select`, `suggestion_card`, `value_comparison`, `avatar`, and `modal_footer`.

Replace hardcoded `hubspot-*` classes with dynamic theme interpolation. Since Tailwind needs to see full class names at build time, use a helper that maps theme + token to the full class:

```elixir
# Add at the top of modal_components.ex
defp theme_class(theme, token) do
  "#{theme}-#{token}"
end
```

Then replace patterns like `border-hubspot-input` with `border-#{theme_class(@theme, "input")}` in the templates.

**IMPORTANT:** Since Tailwind purges classes, add a safelist in `tailwind.config.js`:

```javascript
safelist: [
  {pattern: /^(bg|text|border|accent)-(hubspot|salesforce)-.+/},
],
```

**Step 3: Update HubspotModalComponent to pass theme**

Pass `theme="hubspot"` to all shared component calls to maintain existing behavior.

**Step 4: Run tests**

Run: `mix test`
Expected: All existing tests pass unchanged (HubSpot behavior preserved).

**Step 5: Commit**

```bash
git add lib/social_scribe_web/components/modal_components.ex assets/tailwind.config.js lib/social_scribe_web/live/meeting_live/hubspot_modal_component.ex
git commit -m "refactor: parameterize ModalComponents with theme prop for multi-CRM support"
```

---

### Task 4: Add category grouping to suggestion cards

The reference UI design (image.png) shows suggestions grouped by category (e.g., "Client name", "Account value") with:
- Group-level checkbox + expand/collapse ("Hide details" / "Show details")
- Badge showing "N updates selected" per group
- Individual field rows nested inside each group

The current `suggestion_card` component is flat (no grouping). Add a `suggestion_group` component.

**Files:**
- Modify: `lib/social_scribe_web/components/modal_components.ex`
- Modify: `lib/social_scribe_web/live/meeting_live/hubspot_modal_component.ex` (use new grouped layout)

**Step 1: Add `suggestion_group` component**

Add to `modal_components.ex`:

```elixir
@doc """
Renders a collapsible group of suggestion cards with a group-level checkbox.
"""
attr :name, :string, required: true
attr :suggestions, :list, required: true
attr :theme, :string, default: "hubspot"
attr :expanded, :boolean, default: true

def suggestion_group(assigns) do
  assigns = assign(assigns, :selected_count, Enum.count(assigns.suggestions, & &1.apply))

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
        />
        <span class="font-medium text-sm text-slate-900">{@name}</span>
      </div>
      <div class="flex items-center gap-3">
        <span class={"inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium bg-#{theme_class(@theme, "pill")} text-#{theme_class(@theme, "pill-text")}"}>
          {@selected_count} update{if @selected_count != 1, do: "s"} selected
        </span>
        <button type="button" phx-click="toggle_group_expand" phx-value-group={@name}
          class={"text-sm text-#{theme_class(@theme, "hide")} hover:text-#{theme_class(@theme, "hide-hover")}"}>
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
```

**Step 2: Add grouping logic to suggestion modules**

Both `HubspotSuggestions` and `SalesforceSuggestions` should include a `category` field in their output. Define field-to-category mappings. For Salesforce:

```elixir
@field_categories %{
  "FirstName" => "Contact Info",
  "LastName" => "Contact Info",
  "Email" => "Contact Info",
  "Phone" => "Contact Info",
  "MobilePhone" => "Contact Info",
  "Title" => "Professional Details",
  "Department" => "Professional Details",
  "MailingStreet" => "Mailing Address",
  "MailingCity" => "Mailing Address",
  "MailingState" => "Mailing Address",
  "MailingPostalCode" => "Mailing Address",
  "MailingCountry" => "Mailing Address"
}
```

Add `category: Map.get(@field_categories, suggestion.field, "Other")` to the suggestion map in `generate_suggestions_from_meeting/1`.

**Step 3: Update modal components to group suggestions**

In the modal component's `suggestions_section`, group suggestions by category:

```elixir
grouped = Enum.group_by(@suggestions, & &1.category)
```

Then render each group with `<.suggestion_group>`.

**Step 4: Add toggle_group and toggle_group_expand events**

Add to the modal component:

```elixir
def handle_event("toggle_group", %{"group" => group_name}, socket) do
  # Toggle all suggestions in this group
  group_suggestions = Enum.filter(socket.assigns.suggestions, &(&1.category == group_name))
  all_applied = Enum.all?(group_suggestions, & &1.apply)

  updated = Enum.map(socket.assigns.suggestions, fn s ->
    if s.category == group_name, do: %{s | apply: !all_applied}, else: s
  end)

  {:noreply, assign(socket, suggestions: updated)}
end

def handle_event("toggle_group_expand", %{"group" => group_name}, socket) do
  expanded = Map.update(socket.assigns.expanded_groups, group_name, false, &(!&1))
  {:noreply, assign(socket, expanded_groups: expanded)}
end
```

**Step 5: Run tests and commit**

```bash
mix test
git add lib/social_scribe_web/components/modal_components.ex lib/social_scribe_web/live/meeting_live/hubspot_modal_component.ex
git commit -m "feat: add suggestion category grouping with expand/collapse per reference UI design"
```

---

### Task 5: Move credential loading out of mount/3

Per Phoenix best practice, `mount/3` is called TWICE (once for HTTP request, once for WebSocket connection). Database queries in mount cause duplicate queries.

**Files:**
- Modify: `lib/social_scribe_web/live/meeting_live/show.ex`

**Step 1: Move DB queries to handle_params**

Move `hubspot_credential` (and later `salesforce_credential`) loading from `mount/3` to `handle_params/3`. Initialize with `nil` in mount:

In mount, replace:
```elixir
hubspot_credential = Accounts.get_user_hubspot_credential(socket.assigns.current_user.id)
```
with:
```elixir
|> assign(:hubspot_credential, nil)
```

In handle_params catch-all clause, add credential loading:
```elixir
def handle_params(_params, _uri, socket) do
  hubspot_credential = Accounts.get_user_hubspot_credential(socket.assigns.current_user.id)

  {:noreply,
   socket
   |> assign(:hubspot_credential, hubspot_credential)}
end
```

**Note:** This also applies to the meeting/automations queries already in mount. Consider moving those to handle_params too, but at minimum move the credential queries since they are the new code we control.

**Step 2: Run tests**

Run: `mix test`
Expected: All pass — behavior unchanged, just loading deferred.

**Step 3: Commit**

```bash
git add lib/social_scribe_web/live/meeting_live/show.ex
git commit -m "refactor: move credential loading from mount/3 to handle_params/3 (Phoenix best practice)"
```

---

## Phase 4: OAuth Strategy

### Task 6: Ueberauth Salesforce Strategy + OAuth Module

**Files:**
- Create: `lib/ueberauth/strategy/salesforce/oauth.ex`
- Create: `lib/ueberauth/strategy/salesforce.ex`
- Modify: `config/config.exs`
- Modify: `config/runtime.exs`
- Modify: `config/test.exs`

**Reference files:** `lib/ueberauth/strategy/hubspot.ex` and `lib/ueberauth/strategy/hubspot/oauth.ex`

**Step 1: Create OAuth module**

Create `lib/ueberauth/strategy/salesforce/oauth.ex`:

```elixir
defmodule Ueberauth.Strategy.Salesforce.OAuth do
  @moduledoc """
  OAuth2 for Salesforce.

  Add `client_id` and `client_secret` to your configuration:

      config :ueberauth, Ueberauth.Strategy.Salesforce.OAuth,
        client_id: System.get_env("SALESFORCE_CLIENT_ID"),
        client_secret: System.get_env("SALESFORCE_CLIENT_SECRET")
  """

  use OAuth2.Strategy

  @defaults [
    strategy: __MODULE__,
    site: "https://login.salesforce.com",
    authorize_url: "https://login.salesforce.com/services/oauth2/authorize",
    token_url: "https://login.salesforce.com/services/oauth2/token"
  ]

  def client(opts \\ []) do
    config = Application.get_env(:ueberauth, __MODULE__, [])
    json_library = Ueberauth.json_library()

    opts =
      @defaults
      |> Keyword.merge(config)
      |> Keyword.merge(opts)

    opts
    |> OAuth2.Client.new()
    |> OAuth2.Client.put_serializer("application/json", json_library)
  end

  def authorize_url!(params \\ [], opts \\ []) do
    opts
    |> client()
    |> OAuth2.Client.authorize_url!(params)
  end

  def get_access_token(params \\ [], opts \\ []) do
    client = client(opts)

    config = Application.get_env(:ueberauth, __MODULE__, [])

    params =
      params
      |> Keyword.put(:client_id, config[:client_id])
      |> Keyword.put(:client_secret, config[:client_secret])

    case OAuth2.Client.get_token(client, params) do
      {:ok, %{token: %{access_token: nil}}} ->
        {:error, "No access token received from Salesforce"}

      {:ok, %{token: token}} ->
        {:ok, token}

      {:error, %OAuth2.Response{body: %{"error" => error, "error_description" => desc}}} ->
        {:error, "#{error}: #{desc}"}

      {:error, %OAuth2.Error{reason: reason}} ->
        {:error, reason}
    end
  end

  def get_user_info(access_token, id_url) do
    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Accept", "application/json"}
    ]

    case Tesla.get(tesla_client(), id_url, headers: headers) do
      {:ok, %Tesla.Env{status: 200, body: body}} when is_map(body) ->
        {:ok, body}

      {:ok, %Tesla.Env{status: 200, body: body}} when is_binary(body) ->
        {:ok, Ueberauth.json_library().decode!(body)}

      {:ok, %Tesla.Env{status: status, body: body}} ->
        {:error, "Salesforce user info failed (#{status}): #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp tesla_client do
    Tesla.client([Tesla.Middleware.JSON])
  end

  # OAuth2.Strategy callbacks
  @impl true
  def authorize_url(client, params) do
    OAuth2.Strategy.AuthCode.authorize_url(client, params)
  end

  @impl true
  def get_token(client, params, headers) do
    client
    |> put_header("Content-Type", "application/x-www-form-urlencoded")
    |> OAuth2.Strategy.AuthCode.get_token(params, headers)
  end
end
```

**Step 2: Create Ueberauth Strategy**

Create `lib/ueberauth/strategy/salesforce.ex`:

```elixir
defmodule Ueberauth.Strategy.Salesforce do
  @moduledoc """
  Salesforce Strategy for Ueberauth.
  """

  use Ueberauth.Strategy,
    uid_field: :user_id,
    default_scope: "api refresh_token",
    oauth2_module: Ueberauth.Strategy.Salesforce.OAuth

  alias Ueberauth.Auth.{Credentials, Info, Extra}

  @impl true
  def handle_request!(conn) do
    scopes = conn.params["scope"] || option(conn, :default_scope)

    params =
      [scope: scopes, response_type: "code", redirect_uri: callback_url(conn)]
      |> with_state_param(conn)

    redirect!(conn, Ueberauth.Strategy.Salesforce.OAuth.authorize_url!(params))
  end

  @impl true
  def handle_callback!(%Plug.Conn{params: %{"code" => code}} = conn) do
    case Ueberauth.Strategy.Salesforce.OAuth.get_access_token(
           [code: code, redirect_uri: callback_url(conn)]
         ) do
      {:ok, token} ->
        conn
        |> put_private(:salesforce_token, token)
        |> fetch_user(token)

      {:error, reason} ->
        set_errors!(conn, [error("OAuth2", reason)])
    end
  end

  def handle_callback!(conn) do
    set_errors!(conn, [error("missing_code", "No code received")])
  end

  @impl true
  def handle_cleanup!(conn) do
    conn
    |> put_private(:salesforce_token, nil)
    |> put_private(:salesforce_user, nil)
  end

  @impl true
  def uid(conn) do
    conn.private[:salesforce_user]["user_id"]
  end

  @impl true
  def credentials(conn) do
    token = conn.private[:salesforce_token]

    %Credentials{
      token: token.access_token,
      refresh_token: token.refresh_token,
      token_type: "Bearer",
      expires: true,
      expires_at: nil,
      other: %{
        instance_url: token.other_params["instance_url"],
        issued_at: token.other_params["issued_at"]
      }
    }
  end

  @impl true
  def info(conn) do
    user = conn.private[:salesforce_user] || %{}

    %Info{
      email: user["email"],
      name: user["name"]
    }
  end

  @impl true
  def extra(conn) do
    %Extra{
      raw_info: %{
        token: conn.private[:salesforce_token],
        user: conn.private[:salesforce_user]
      }
    }
  end

  defp fetch_user(conn, token) do
    # The "id" field in token response is the identity URL
    id_url = token.other_params["id"]

    if id_url do
      case Ueberauth.Strategy.Salesforce.OAuth.get_user_info(token.access_token, id_url) do
        {:ok, user} ->
          put_private(conn, :salesforce_user, user)

        {:error, reason} ->
          set_errors!(conn, [error("user_info", reason)])
      end
    else
      set_errors!(conn, [error("missing_id_url", "No identity URL in Salesforce token response")])
    end
  end

  defp option(conn, key) do
    Keyword.get(options(conn), key, Keyword.get(default_options(), key))
  end
end
```

**Step 3: Update configs**

In `config/config.exs` — add `salesforce` to Ueberauth providers list:
```elixir
salesforce: {Ueberauth.Strategy.Salesforce, []}
```

**NOTE:** Do NOT add the Oban cron entry for `SalesforceTokenRefresher` here yet — the worker module doesn't exist until Task 6. Add the cron entry in Task 6 instead to avoid compile errors.

In `config/runtime.exs` — add near the HubSpot config:
```elixir
config :ueberauth, Ueberauth.Strategy.Salesforce.OAuth,
  client_id: System.get_env("SALESFORCE_CLIENT_ID"),
  client_secret: System.get_env("SALESFORCE_CLIENT_SECRET")
```

In `config/test.exs` — add:
```elixir
config :ueberauth, Ueberauth.Strategy.Salesforce.OAuth,
  client_id: "test_salesforce_client_id",
  client_secret: "test_salesforce_client_secret"
```

**Step 4: Run tests**

Run: `mix test`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/ueberauth/strategy/salesforce.ex lib/ueberauth/strategy/salesforce/oauth.ex config/config.exs config/runtime.exs config/test.exs
git commit -m "feat: add Salesforce Ueberauth OAuth2 strategy"
```

---

### Task 7: Auth Controller + Settings Page

**Files:**
- Modify: `lib/social_scribe_web/controllers/auth_controller.ex`
- Modify: `lib/social_scribe_web/live/user_settings_live.ex`
- Modify: `lib/social_scribe_web/live/user_settings_live.html.heex`

**Step 1: Add Salesforce callback to AuthController**

In `lib/social_scribe_web/controllers/auth_controller.ex`, add a new `callback/2` clause (alongside the HubSpot one):

```elixir
def callback(%{assigns: %{ueberauth_auth: auth, current_user: user}} = conn, %{
      "provider" => "salesforce"
    })
    when not is_nil(user) do
  Logger.info("Salesforce OAuth callback")

  credential_attrs = %{
    user_id: user.id,
    provider: "salesforce",
    uid: to_string(auth.uid),
    token: auth.credentials.token,
    refresh_token: auth.credentials.refresh_token,
    expires_at: DateTime.add(DateTime.utc_now(), 7200, :second),
    email: auth.info.email,
    instance_url: auth.credentials.other[:instance_url]
  }

  case Accounts.find_or_create_salesforce_credential(user, credential_attrs) do
    {:ok, _credential} ->
      Logger.info("Salesforce account connected for user #{user.id}")

      conn
      |> put_flash(:info, "Salesforce account connected successfully!")
      |> redirect(to: ~p"/dashboard/settings")

    {:error, reason} ->
      Logger.error("Failed to save Salesforce credential: #{inspect(reason)}")

      conn
      |> put_flash(:error, "Could not connect Salesforce account.")
      |> redirect(to: ~p"/dashboard/settings")
  end
end
```

**Step 2: Update UserSettingsLive mount**

In `lib/social_scribe_web/live/user_settings_live.ex`, add to mount:
```elixir
salesforce_accounts = Accounts.list_user_credentials(current_user, provider: "salesforce")
```
And add assign: `|> assign(:salesforce_accounts, salesforce_accounts)`

**Step 3: Update UserSettingsLive template**

In `lib/social_scribe_web/live/user_settings_live.html.heex`, add a Salesforce section after the HubSpot section (follow the same pattern):

```heex
<div class="bg-white shadow rounded-lg p-6 mt-6">
  <h2 class="text-lg font-medium text-gray-900">Salesforce</h2>
  <p class="mt-1 text-sm text-gray-500">Connect your Salesforce account to update CRM contacts from meetings.</p>

  <%= if not Enum.empty?(@salesforce_accounts) do %>
    <ul class="mt-4 space-y-4">
      <li :for={account <- @salesforce_accounts} class="flex items-center justify-between">
        <div>
          <span class="text-sm font-medium text-gray-700">UID: {account.uid}</span>
          <span :if={account.email} class="text-sm text-gray-500 ml-2">({account.email})</span>
        </div>
      </li>
    </ul>
  <% else %>
    <p class="mt-4 text-sm text-gray-500">You haven't connected a Salesforce account yet.</p>
  <% end %>

  <div class="mt-4">
    <.link
      href={~p"/auth/salesforce"}
      class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700"
    >
      Connect Salesforce
    </.link>
  </div>
</div>
```

**Step 4: Run tests**

Run: `mix test`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/social_scribe_web/controllers/auth_controller.ex lib/social_scribe_web/live/user_settings_live.ex lib/social_scribe_web/live/user_settings_live.html.heex
git commit -m "feat: add Salesforce OAuth callback and settings UI"
```

---

## Phase 5: API Layer

### Task 8: SalesforceApiBehaviour + SalesforceApi

**Files:**
- Create: `lib/social_scribe/salesforce_api_behaviour.ex`
- Create: `lib/social_scribe/salesforce_api.ex`
- Create: `test/social_scribe/salesforce_api_test.exs`
- Modify: `test/test_helper.exs`

**Reference:** `lib/social_scribe/hubspot_api_behaviour.ex` (exact pattern to follow)

**Step 1: Create behaviour**

Create `lib/social_scribe/salesforce_api_behaviour.ex`:

```elixir
defmodule SocialScribe.SalesforceApiBehaviour do
  @moduledoc """
  Behaviour for the Salesforce API.
  Delegates to the configured implementation (real or mock).
  """

  alias SocialScribe.Accounts.UserCredential

  @callback search_contacts(credential :: UserCredential.t(), query :: String.t()) ::
              {:ok, list(map())} | {:error, any()}

  @callback get_contact(credential :: UserCredential.t(), contact_id :: String.t()) ::
              {:ok, map()} | {:error, any()}

  @callback update_contact(
              credential :: UserCredential.t(),
              contact_id :: String.t(),
              updates :: map()
            ) ::
              {:ok, :updated} | {:error, any()}

  @callback apply_updates(
              credential :: UserCredential.t(),
              contact_id :: String.t(),
              updates_list :: list(map())
            ) ::
              {:ok, :updated | :no_updates} | {:error, any()}

  def search_contacts(credential, query) do
    impl().search_contacts(credential, query)
  end

  def get_contact(credential, contact_id) do
    impl().get_contact(credential, contact_id)
  end

  def update_contact(credential, contact_id, updates) do
    impl().update_contact(credential, contact_id, updates)
  end

  def apply_updates(credential, contact_id, updates_list) do
    impl().apply_updates(credential, contact_id, updates_list)
  end

  defp impl do
    Application.get_env(:social_scribe, :salesforce_api, SocialScribe.SalesforceApi)
  end
end
```

**Step 2: Register Mox mock**

Add to `test/test_helper.exs`:
```elixir
Mox.defmock(SocialScribe.SalesforceApiMock, for: SocialScribe.SalesforceApiBehaviour)
Application.put_env(:social_scribe, :salesforce_api, SocialScribe.SalesforceApiMock)
```

**Step 3: Write failing tests**

Create `test/social_scribe/salesforce_api_test.exs`:

```elixir
defmodule SocialScribe.SalesforceApiTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.SalesforceApi

  import SocialScribe.AccountsFixtures

  describe "format_contact/1" do
    test "normalizes Salesforce record to internal format" do
      record = %{
        "Id" => "003xx000004TMMa",
        "FirstName" => "John",
        "LastName" => "Smith",
        "Email" => "john@example.com",
        "Phone" => "555-1234",
        "MobilePhone" => nil,
        "Title" => "VP Engineering",
        "Department" => "Engineering",
        "MailingStreet" => "123 Main St",
        "MailingCity" => "San Francisco",
        "MailingState" => "CA",
        "MailingPostalCode" => "94105",
        "MailingCountry" => "US",
        "Account" => %{"Name" => "Acme Corp"}
      }

      contact = SalesforceApi.format_contact(record)

      assert contact.id == "003xx000004TMMa"
      # Must use :firstname/:lastname to match contact_select component
      assert contact.firstname == "John"
      assert contact.lastname == "Smith"
      assert contact.email == "john@example.com"
      assert contact.phone == "555-1234"
      assert contact.jobtitle == "VP Engineering"
      assert contact.company == "Acme Corp"
      assert contact.display_name == "John Smith"
    end

    test "handles missing Account gracefully" do
      record = %{
        "Id" => "003xx",
        "FirstName" => "Jane",
        "LastName" => "Doe",
        "Email" => "jane@example.com",
        "Phone" => nil,
        "MobilePhone" => nil,
        "Title" => nil,
        "Department" => nil,
        "MailingStreet" => nil,
        "MailingCity" => nil,
        "MailingState" => nil,
        "MailingPostalCode" => nil,
        "MailingCountry" => nil
      }

      contact = SalesforceApi.format_contact(record)
      assert contact.company == nil
      assert contact.display_name == "Jane Doe"
    end
  end

  describe "apply_updates/3" do
    test "returns {:ok, :no_updates} when all updates have apply: false" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      updates = [
        %{field: "Phone", new_value: "555-1234", apply: false},
        %{field: "Email", new_value: "new@test.com", apply: false}
      ]

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003xx", updates)
    end

    test "returns {:ok, :no_updates} when updates list is empty" do
      user = user_fixture()
      credential = salesforce_credential_fixture(%{user_id: user.id})

      assert {:ok, :no_updates} = SalesforceApi.apply_updates(credential, "003xx", [])
    end
  end
end
```

**Step 4: Run tests to verify they fail**

Run: `mix test test/social_scribe/salesforce_api_test.exs`
Expected: FAIL — module doesn't exist

**Step 5: Implement SalesforceApi**

Create `lib/social_scribe/salesforce_api.ex`:

```elixir
defmodule SocialScribe.SalesforceApi do
  @moduledoc """
  Salesforce REST API client.

  Key differences from HubSpot:
  - Uses dynamic instance_url from credential (not fixed base URL)
  - SOQL for structured queries (not JSON filter groups)
  - PascalCase field names (FirstName, not firstname)
  - Update returns 204 No Content (not the updated object)
  - No expires_in in token response — assume 2hr session
  """

  @behaviour SocialScribe.SalesforceApiBehaviour

  require Logger

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.SalesforceTokenRefresher

  @api_version "v62.0"

  @contact_fields ~w(
    Id FirstName LastName Email Phone MobilePhone Title
    Department MailingStreet MailingCity MailingState
    MailingPostalCode MailingCountry
  )

  # Maps Salesforce PascalCase to internal atom keys matching HubSpot format
  # (contact_select component expects :firstname, :lastname, etc.)
  @field_mapping %{
    "FirstName" => :firstname,
    "LastName" => :lastname,
    "Email" => :email,
    "Phone" => :phone,
    "MobilePhone" => :mobilephone,
    "Title" => :jobtitle,
    "Department" => :department,
    "MailingStreet" => :address,
    "MailingCity" => :city,
    "MailingState" => :state,
    "MailingPostalCode" => :zip,
    "MailingCountry" => :country
  }

  defp client(credential) do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, credential.instance_url},
      Tesla.Middleware.JSON,
      {Tesla.Middleware.Headers, [{"Authorization", "Bearer #{credential.token}"}]}
    ])
  end

  @impl true
  def search_contacts(%UserCredential{} = credential, query) when is_binary(query) do
    with_token_refresh(credential, fn cred ->
      escaped = escape_soql_string(query)
      fields = Enum.join(@contact_fields, ", ")

      soql =
        "SELECT #{fields}, Account.Name FROM Contact " <>
          "WHERE FirstName LIKE '%#{escaped}%' OR LastName LIKE '%#{escaped}%' OR Email LIKE '%#{escaped}%' " <>
          "ORDER BY LastModifiedDate DESC LIMIT 20"

      encoded = URI.encode(soql)

      case Tesla.get(client(cred), "/services/data/#{@api_version}/query/?q=#{encoded}") do
        {:ok, %Tesla.Env{status: 200, body: %{"records" => records}}} ->
          {:ok, Enum.map(records, &format_contact/1)}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @impl true
  def get_contact(%UserCredential{} = credential, contact_id) do
    with_token_refresh(credential, fn cred ->
      fields = Enum.join(@contact_fields, ",")

      case Tesla.get(
             client(cred),
             "/services/data/#{@api_version}/sobjects/Contact/#{contact_id}?fields=#{fields}"
           ) do
        {:ok, %Tesla.Env{status: 200, body: body}} ->
          {:ok, format_contact(body)}

        {:ok, %Tesla.Env{status: 404}} ->
          {:error, :not_found}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @impl true
  def update_contact(%UserCredential{} = credential, contact_id, updates) when is_map(updates) do
    with_token_refresh(credential, fn cred ->
      case Tesla.patch(
             client(cred),
             "/services/data/#{@api_version}/sobjects/Contact/#{contact_id}",
             updates
           ) do
        {:ok, %Tesla.Env{status: status}} when status in [200, 204] ->
          {:ok, :updated}

        {:ok, %Tesla.Env{status: status, body: body}} ->
          {:error, {:api_error, status, body}}

        {:error, reason} ->
          {:error, {:http_error, reason}}
      end
    end)
  end

  @impl true
  def apply_updates(%UserCredential{} = credential, contact_id, updates_list) when is_list(updates_list) do
    applicable =
      updates_list
      |> Enum.filter(& &1[:apply])
      |> Enum.into(%{}, fn update -> {update[:field], update[:new_value]} end)

    if map_size(applicable) == 0 do
      {:ok, :no_updates}
    else
      update_contact(credential, contact_id, applicable)
    end
  end

  @doc """
  Formats a Salesforce API contact record into the internal representation.
  Uses :firstname/:lastname keys to match the contact_select UI component.
  """
  def format_contact(record) do
    company =
      case record do
        %{"Account" => %{"Name" => name}} -> name
        _ -> nil
      end

    base =
      Enum.reduce(@field_mapping, %{}, fn {sf_field, internal_key}, acc ->
        Map.put(acc, internal_key, record[sf_field])
      end)

    base
    |> Map.put(:id, record["Id"])
    |> Map.put(:company, company)
    |> Map.put(:display_name, build_display_name(record))
  end

  defp build_display_name(record) do
    name =
      [record["FirstName"], record["LastName"]]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

    if name == "", do: record["Email"] || "Unknown", else: name
  end

  # Escapes user input for safe inclusion in SOQL string literals.
  # Salesforce SOQL requires escaping single quotes, backslashes, and control characters.
  defp escape_soql_string(str) do
    str
    |> String.replace("\\", "\\\\")
    |> String.replace("'", "\\'")
    |> String.replace("_", "\\_")
    |> String.replace("%", "\\%")
  end

  defp with_token_refresh(%UserCredential{} = credential, api_fn) do
    case SalesforceTokenRefresher.ensure_valid_token(credential) do
      {:ok, refreshed_cred} ->
        case api_fn.(refreshed_cred) do
          {:error, {:api_error, 401, _body}} ->
            Logger.info("Salesforce token expired, refreshing and retrying...")

            case SalesforceTokenRefresher.refresh_credential(refreshed_cred) do
              {:ok, fresh_cred} -> api_fn.(fresh_cred)
              error -> error
            end

          other ->
            other
        end

      {:error, _} = error ->
        error
    end
  end
end
```

**Step 6: Run tests**

Run: `mix test test/social_scribe/salesforce_api_test.exs`
Expected: All pass

**Step 7: Commit**

```bash
git add lib/social_scribe/salesforce_api_behaviour.ex lib/social_scribe/salesforce_api.ex test/social_scribe/salesforce_api_test.exs test/test_helper.exs
git commit -m "feat: add SalesforceApi behaviour and implementation with SOQL search"
```

---

### Task 9: Token Refresher + Oban Worker

**Files:**
- Create: `lib/social_scribe/salesforce_token_refresher.ex`
- Create: `lib/social_scribe/workers/salesforce_token_refresher.ex`
- Create: `test/social_scribe/salesforce_token_refresher_test.exs`
- Modify: `config/config.exs` (add Oban cron entry NOW that the worker module exists)

**Reference:** `lib/social_scribe/hubspot_token_refresher.ex` and `lib/social_scribe/workers/hubspot_token_refresher.ex`

**Step 1: Write failing test**

Create `test/social_scribe/salesforce_token_refresher_test.exs`:

```elixir
defmodule SocialScribe.SalesforceTokenRefresherTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.SalesforceTokenRefresher

  import SocialScribe.AccountsFixtures

  describe "ensure_valid_token/1" do
    test "returns credential unchanged when token is not expired" do
      credential =
        salesforce_credential_fixture(%{
          expires_at: DateTime.add(DateTime.utc_now(), 3600, :second)
        })

      assert {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert result.id == credential.id
      assert result.token == credential.token
    end

    test "returns credential unchanged when token expires in more than 5 minutes" do
      credential =
        salesforce_credential_fixture(%{
          expires_at: DateTime.add(DateTime.utc_now(), 600, :second)
        })

      assert {:ok, result} = SalesforceTokenRefresher.ensure_valid_token(credential)
      assert result.id == credential.id
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/social_scribe/salesforce_token_refresher_test.exs`
Expected: FAIL

**Step 3: Implement SalesforceTokenRefresher**

Create `lib/social_scribe/salesforce_token_refresher.ex`:

```elixir
defmodule SocialScribe.SalesforceTokenRefresher do
  @moduledoc """
  Handles refreshing Salesforce OAuth tokens.

  Key differences from HubSpot:
  - Refresh token is stable (no rotation)
  - No expires_in in response — assume 2hr session timeout
  - issued_at is in milliseconds
  """

  require Logger

  @salesforce_token_url "https://login.salesforce.com/services/oauth2/token"
  @refresh_buffer_seconds 300
  @default_token_lifetime_seconds 7200

  def refresh_token(refresh_token_string) do
    config = Application.get_env(:ueberauth, Ueberauth.Strategy.Salesforce.OAuth, [])

    body = %{
      grant_type: "refresh_token",
      refresh_token: refresh_token_string,
      client_id: config[:client_id],
      client_secret: config[:client_secret]
    }

    case Tesla.post(client(), @salesforce_token_url, body) do
      {:ok, %Tesla.Env{status: 200, body: response_body}} ->
        {:ok, response_body}

      {:ok, %Tesla.Env{status: status, body: error_body}} ->
        Logger.error("Salesforce token refresh failed: #{status} - #{inspect(error_body)}")
        {:error, {status, error_body}}

      {:error, reason} ->
        Logger.error("Salesforce token refresh error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def refresh_credential(credential) do
    case refresh_token(credential.refresh_token) do
      {:ok, response} ->
        # Salesforce refresh typically does NOT return a new refresh_token,
        # but orgs with "Rotate Refresh Tokens" enabled (opt-in since Spring 2024)
        # will return a new one. Store it defensively if present.
        attrs =
          %{
            token: response["access_token"],
            expires_at: DateTime.add(DateTime.utc_now(), @default_token_lifetime_seconds, :second),
            instance_url: response["instance_url"] || credential.instance_url
          }
          |> maybe_put_refresh_token(response)

        SocialScribe.Accounts.update_user_credential(credential, attrs)

      {:error, _} = error ->
        error
    end
  end

  def ensure_valid_token(credential) do
    if token_expired_or_expiring?(credential) do
      refresh_credential(credential)
    else
      {:ok, credential}
    end
  end

  defp token_expired_or_expiring?(credential) do
    case credential.expires_at do
      nil ->
        true

      expires_at ->
        buffer = DateTime.add(DateTime.utc_now(), @refresh_buffer_seconds, :second)
        DateTime.compare(expires_at, buffer) == :lt
    end
  end

  # Salesforce orgs with "Rotate Refresh Tokens" enabled return a new refresh_token.
  # Store it if present; otherwise keep the existing one.
  defp maybe_put_refresh_token(attrs, %{"refresh_token" => new_rt}) when is_binary(new_rt),
    do: Map.put(attrs, :refresh_token, new_rt)

  defp maybe_put_refresh_token(attrs, _response), do: attrs

  defp client do
    Tesla.client([
      Tesla.Middleware.FormUrlencoded,
      Tesla.Middleware.JSON
    ])
  end
end
```

**Step 4: Create Oban worker**

Create `lib/social_scribe/workers/salesforce_token_refresher.ex`:

```elixir
defmodule SocialScribe.Workers.SalesforceTokenRefresher do
  @moduledoc """
  Oban cron worker that proactively refreshes expiring Salesforce tokens.
  Runs every 30 minutes. Salesforce access tokens last ~2 hours.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger

  import Ecto.Query

  alias SocialScribe.Accounts.UserCredential
  alias SocialScribe.{Repo, SalesforceTokenRefresher}

  @refresh_threshold_minutes 60

  @impl Oban.Worker
  def perform(_job) do
    Logger.info("Running proactive Salesforce token refresh check...")

    credentials = get_expiring_salesforce_credentials()

    case credentials do
      [] ->
        Logger.debug("No Salesforce tokens expiring soon")
        :ok

      credentials ->
        Logger.info("Found #{length(credentials)} Salesforce token(s) expiring soon, refreshing...")
        refresh_all(credentials)
    end
  end

  defp get_expiring_salesforce_credentials do
    threshold = DateTime.add(DateTime.utc_now(), @refresh_threshold_minutes, :minute)

    from(uc in UserCredential,
      where:
        uc.provider == "salesforce" and
          uc.expires_at < ^threshold and
          not is_nil(uc.refresh_token)
    )
    |> Repo.all()
  end

  defp refresh_all(credentials) do
    Enum.each(credentials, fn credential ->
      case SalesforceTokenRefresher.refresh_credential(credential) do
        {:ok, _} ->
          Logger.info("Refreshed Salesforce token for credential #{credential.id}")

        {:error, reason} ->
          Logger.error(
            "Failed to refresh Salesforce token for credential #{credential.id}: #{inspect(reason)}"
          )
      end
    end)

    :ok
  end
end
```

**Step 5: Add Oban cron entry**

Now that the worker module exists, add to `config/config.exs` in the Oban cron list:
```elixir
{"*/30 * * * *", SocialScribe.Workers.SalesforceTokenRefresher}
```

**Step 6: Run tests**

Run: `mix test test/social_scribe/salesforce_token_refresher_test.exs && mix test`
Expected: All pass

**Step 7: Commit**

```bash
git add lib/social_scribe/salesforce_token_refresher.ex lib/social_scribe/workers/salesforce_token_refresher.ex test/social_scribe/salesforce_token_refresher_test.exs config/config.exs
git commit -m "feat: add Salesforce token refresh with 2hr lifecycle and Oban cron worker"
```

---

## Phase 6: AI Suggestions

### Task 10: Add `generate_salesforce_suggestions` callback + implementation

**Files:**
- Modify: `lib/social_scribe/ai_content_generator_api.ex`
- Modify: `lib/social_scribe/ai_content_generator.ex`

**Step 1: Add callback to behaviour**

In `lib/social_scribe/ai_content_generator_api.ex`, add:

```elixir
@callback generate_salesforce_suggestions(map()) :: {:ok, list(map())} | {:error, any()}

def generate_salesforce_suggestions(meeting) do
  impl().generate_salesforce_suggestions(meeting)
end
```

**Step 2: Implement in AIContentGenerator**

In `lib/social_scribe/ai_content_generator.ex`, add:

```elixir
@impl SocialScribe.AIContentGeneratorApi
def generate_salesforce_suggestions(meeting) do
  case Meetings.generate_prompt_for_meeting(meeting) do
    {:error, reason} ->
      {:error, reason}

    {:ok, meeting_prompt} ->
      prompt = """
      You are an AI assistant that extracts contact information updates from meeting transcripts.

      Analyze the following meeting transcript and extract any information that could be used to update a Salesforce Contact record.

      Look for mentions of:
      - Phone numbers (Phone, MobilePhone)
      - Email addresses (Email)
      - Job title/role (Title)
      - Department (Department)
      - Physical address details (MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry)

      IMPORTANT: Only extract information that is EXPLICITLY mentioned in the transcript. Do not infer or guess.

      The transcript includes timestamps in [MM:SS] format at the start of each line.

      Return your response as a JSON array of objects. Each object should have:
      - "field": the Salesforce field name (use exactly: FirstName, LastName, Email, Phone, MobilePhone, Title, Department, MailingStreet, MailingCity, MailingState, MailingPostalCode, MailingCountry)
      - "value": the extracted value
      - "context": a brief quote of where this was mentioned
      - "timestamp": the timestamp in MM:SS format where this was mentioned

      If no contact information updates are found, return an empty array: []

      Example response format:
      [
        {"field": "Phone", "value": "555-123-4567", "context": "John mentioned 'you can reach me at 555-123-4567'", "timestamp": "01:23"},
        {"field": "Title", "value": "CTO", "context": "Sarah mentioned she was promoted to CTO", "timestamp": "05:47"}
      ]

      ONLY return valid JSON, no other text.

      Meeting transcript:
      #{meeting_prompt}
      """

      case call_gemini(prompt) do
        {:ok, response} ->
          parse_salesforce_suggestions(response)

        {:error, reason} ->
          {:error, reason}
      end
  end
end

defp parse_salesforce_suggestions(response) do
  cleaned =
    response
    |> String.trim()
    |> String.replace(~r/^```json\n?/, "")
    |> String.replace(~r/\n?```$/, "")
    |> String.trim()

  case Jason.decode(cleaned) do
    {:ok, suggestions} when is_list(suggestions) ->
      formatted =
        suggestions
        |> Enum.filter(&is_map/1)
        |> Enum.map(fn s ->
          %{
            field: s["field"],
            value: s["value"],
            context: s["context"],
            timestamp: s["timestamp"]
          }
        end)
        |> Enum.filter(fn s -> s.field != nil and s.value != nil end)

      {:ok, formatted}

    {:ok, _} ->
      {:ok, []}

    {:error, _} ->
      {:ok, []}
  end
end
```

**Step 3: Run tests**

Run: `mix test`
Expected: All pass

**Step 4: Commit**

```bash
git add lib/social_scribe/ai_content_generator_api.ex lib/social_scribe/ai_content_generator.ex
git commit -m "feat: add generate_salesforce_suggestions AI callback with Salesforce field names"
```

---

### Task 11: SalesforceSuggestions module

**Files:**
- Create: `lib/social_scribe/salesforce_suggestions.ex`
- Create: `test/social_scribe/salesforce_suggestions_test.exs`

**Reference:** `lib/social_scribe/hubspot_suggestions.ex`

**Step 1: Write failing test**

Create `test/social_scribe/salesforce_suggestions_test.exs`:

```elixir
defmodule SocialScribe.SalesforceSuggestionsTest do
  use SocialScribe.DataCase, async: true

  alias SocialScribe.SalesforceSuggestions

  describe "merge_with_contact/2" do
    test "merges suggestions with contact data and filters unchanged values" do
      suggestions = [
        %{
          field: "Phone",
          label: "Phone",
          current_value: nil,
          new_value: "555-1234",
          context: "mentioned phone",
          timestamp: "02:35",
          apply: true,
          has_change: true
        },
        %{
          field: "Title",
          label: "Job Title",
          current_value: nil,
          new_value: "VP Engineering",
          context: "mentioned title",
          timestamp: "03:10",
          apply: true,
          has_change: true
        }
      ]

      contact = %{
        id: "003xx",
        firstname: "John",
        lastname: "Smith",
        email: "john@example.com",
        phone: nil,
        jobtitle: "VP Engineering",
        company: "Acme Corp"
      }

      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      # Title already matches — should be filtered out
      assert length(result) == 1
      assert hd(result).field == "Phone"
      assert hd(result).current_value == nil
      assert hd(result).new_value == "555-1234"
    end

    test "returns empty list when all suggestions match current values" do
      suggestions = [
        %{
          field: "Email",
          label: "Email",
          current_value: nil,
          new_value: "john@example.com",
          context: "mentioned email",
          timestamp: "01:00",
          apply: true,
          has_change: true
        }
      ]

      contact = %{email: "john@example.com"}

      assert SalesforceSuggestions.merge_with_contact(suggestions, contact) == []
    end

    test "handles empty suggestions list" do
      assert SalesforceSuggestions.merge_with_contact([], %{}) == []
    end
  end

  describe "generate_suggestions_from_meeting/1" do
    test "transforms AI suggestions into structured format" do
      import Mox
      setup_mox()

      meeting = %{id: 1}

      SocialScribe.AIContentGeneratorMock
      |> expect(:generate_salesforce_suggestions, fn _meeting ->
        {:ok,
         [
           %{field: "Phone", value: "555-9999", context: "gave phone number", timestamp: "02:30"},
           %{field: "Title", value: "CTO", context: "promoted to CTO", timestamp: "05:00"}
         ]}
      end)

      assert {:ok, suggestions} = SalesforceSuggestions.generate_suggestions_from_meeting(meeting)
      assert length(suggestions) == 2

      phone = Enum.find(suggestions, &(&1.field == "Phone"))
      assert phone.new_value == "555-9999"
      assert phone.label == "Phone"
      assert phone.apply == true
      assert phone.has_change == true
    end

    defp setup_mox do
      Mox.verify_on_exit!()
    end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/social_scribe/salesforce_suggestions_test.exs`
Expected: FAIL

**Step 3: Implement**

Create `lib/social_scribe/salesforce_suggestions.ex`:

```elixir
defmodule SocialScribe.SalesforceSuggestions do
  @moduledoc """
  Generates AI-powered suggestions for Salesforce contact updates
  based on meeting transcripts.
  """

  alias SocialScribe.AIContentGeneratorApi

  @field_labels %{
    "FirstName" => "First Name",
    "LastName" => "Last Name",
    "Email" => "Email",
    "Phone" => "Phone",
    "MobilePhone" => "Mobile Phone",
    "Title" => "Job Title",
    "Department" => "Department",
    "MailingStreet" => "Mailing Street",
    "MailingCity" => "Mailing City",
    "MailingState" => "Mailing State",
    "MailingPostalCode" => "Mailing Postal Code",
    "MailingCountry" => "Mailing Country"
  }

  # Maps Salesforce PascalCase field names to internal contact atom keys
  # These must match the keys from SalesforceApi.format_contact/1
  @field_to_contact_key %{
    "FirstName" => :firstname,
    "LastName" => :lastname,
    "Email" => :email,
    "Phone" => :phone,
    "MobilePhone" => :mobilephone,
    "Title" => :jobtitle,
    "Department" => :department,
    "MailingStreet" => :address,
    "MailingCity" => :city,
    "MailingState" => :state,
    "MailingPostalCode" => :zip,
    "MailingCountry" => :country
  }

  # Category grouping for UI display (matches reference design)
  @field_categories %{
    "FirstName" => "Contact Info",
    "LastName" => "Contact Info",
    "Email" => "Contact Info",
    "Phone" => "Contact Info",
    "MobilePhone" => "Contact Info",
    "Title" => "Professional Details",
    "Department" => "Professional Details",
    "MailingStreet" => "Mailing Address",
    "MailingCity" => "Mailing Address",
    "MailingState" => "Mailing Address",
    "MailingPostalCode" => "Mailing Address",
    "MailingCountry" => "Mailing Address"
  }

  @doc """
  Generates suggestions from a meeting transcript without contact data.
  Called first, then merged with contact after selection.
  """
  def generate_suggestions_from_meeting(meeting) do
    case AIContentGeneratorApi.generate_salesforce_suggestions(meeting) do
      {:ok, ai_suggestions} ->
        suggestions =
          ai_suggestions
          |> Enum.map(fn suggestion ->
            %{
              field: suggestion.field,
              label: Map.get(@field_labels, suggestion.field, suggestion.field),
              category: Map.get(@field_categories, suggestion.field, "Other"),
              current_value: nil,
              new_value: suggestion.value,
              context: Map.get(suggestion, :context),
              timestamp: Map.get(suggestion, :timestamp),
              apply: true,
              has_change: true
            }
          end)

        {:ok, suggestions}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Merges AI suggestions with actual contact data.
  Fills in current_value and filters out suggestions where value hasn't changed.
  """
  def merge_with_contact(suggestions, contact) when is_list(suggestions) do
    suggestions
    |> Enum.map(fn suggestion ->
      contact_key = Map.get(@field_to_contact_key, suggestion.field)
      current_value = if contact_key, do: Map.get(contact, contact_key), else: nil

      %{
        suggestion
        | current_value: current_value,
          has_change: current_value != suggestion.new_value,
          apply: true
      }
    end)
    |> Enum.filter(& &1.has_change)
  end
end
```

**Step 4: Run tests**

Run: `mix test test/social_scribe/salesforce_suggestions_test.exs`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/social_scribe/salesforce_suggestions.ex test/social_scribe/salesforce_suggestions_test.exs
git commit -m "feat: add SalesforceSuggestions with field mapping and merge logic"
```

---

## Phase 7: LiveView UI

### Task 12: Salesforce modal wrapper

**Files:**
- Modify: `lib/social_scribe_web/components/modal_components.ex`

**NOTE:** Tailwind Salesforce colors were already added in Task 3 (Phase 3). No tailwind.config.js changes needed here.

**Step 1: Add `salesforce_modal` to ModalComponents**

In `lib/social_scribe_web/components/modal_components.ex`, add after the existing `hubspot_modal/1`:

```elixir
@doc """
Renders a Salesforce-styled modal wrapper.
"""
attr :id, :string, required: true
attr :show, :boolean, default: false
attr :on_cancel, JS, default: %JS{}
slot :inner_block, required: true

def salesforce_modal(assigns) do
  ~H"""
  <div
    id={@id}
    phx-mounted={@show && show_modal(@id)}
    phx-remove={hide_modal(@id)}
    data-cancel={JS.exec(@on_cancel, "phx-remove")}
    class="relative z-50 hidden"
  >
    <div id={"#{@id}-bg"} class="bg-salesforce-overlay/90 fixed inset-0 transition-opacity" aria-hidden="true" />
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
```

**Step 2: Run tests**

Run: `mix test`
Expected: All pass

**Step 3: Commit**

```bash
git add lib/social_scribe_web/components/modal_components.ex
git commit -m "feat: add salesforce_modal component"
```

---

### Task 13: SalesforceModalComponent

**Files:**
- Create: `lib/social_scribe_web/live/meeting_live/salesforce_modal_component.ex`

**Reference:** `lib/social_scribe_web/live/meeting_live/hubspot_modal_component.ex` — copy and adapt.

**Step 1: Create the component**

Create `lib/social_scribe_web/live/meeting_live/salesforce_modal_component.ex`:

```elixir
defmodule SocialScribeWeb.MeetingLive.SalesforceModalComponent do
  use SocialScribeWeb, :live_component

  import SocialScribeWeb.ModalComponents

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :patch, ~p"/dashboard/meetings/#{assigns.meeting}")
    assigns = assign_new(assigns, :modal_id, fn -> "salesforce-modal-wrapper" end)

    ~H"""
    <div class="space-y-6">
      <div>
        <h2 id={"#{@modal_id}-title"} class="text-xl font-medium tracking-tight text-slate-900">Update in Salesforce</h2>
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
          theme="salesforce"
        />

      <%= if @selected_contact do %>
        <.suggestions_section
          suggestions={@suggestions}
          loading={@loading}
          myself={@myself}
          patch={@patch}
        />
      <% end %>
    </div>
    """
  end

  attr :suggestions, :list, required: true
  attr :loading, :boolean, required: true
  attr :myself, :any, required: true
  attr :patch, :string, required: true

  defp suggestions_section(assigns) do
    assigns = assign(assigns, :selected_count, Enum.count(assigns.suggestions, & &1.apply))

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
                :for={{category, group_suggestions} <- group_suggestions(@suggestions)}
                name={category}
                suggestions={group_suggestions}
                theme="salesforce"
                expanded={Map.get(@expanded_groups, category, true)}
              />
            </div>

            <.modal_footer
              cancel_patch={@patch}
              submit_text="Update Salesforce"
              submit_class="bg-salesforce-button hover:bg-salesforce-button-hover"
              disabled={@selected_count == 0}
              loading={@loading}
              loading_text="Updating..."
              info_text={"1 object, #{@selected_count} field#{if @selected_count != 1, do: "s"} in 1 integration selected to update"}
              theme="salesforce"
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

    {:ok, socket}
  end

  defp group_suggestions(suggestions) do
    suggestions
    |> Enum.group_by(&Map.get(&1, :category, "Other"))
    |> Enum.sort_by(fn {category, _} -> category end)
  end

  defp maybe_select_all_suggestions(socket, %{suggestions: suggestions}) when is_list(suggestions) do
    assign(socket, suggestions: Enum.map(suggestions, &Map.put(&1, :apply, true)))
  end

  defp maybe_select_all_suggestions(socket, _assigns), do: socket

  @impl true
  def handle_event("contact_search", %{"value" => query}, socket) do
    query = String.trim(query)

    if String.length(query) >= 2 do
      socket = assign(socket, searching: true, error: nil, query: query, dropdown_open: true)
      send(self(), {:salesforce_search, query, socket.assigns.credential})
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
      query = "#{socket.assigns.selected_contact.firstname} #{socket.assigns.selected_contact.lastname}"
      send(self(), {:salesforce_search, query, socket.assigns.credential})
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_contact", %{"id" => contact_id}, socket) do
    contact = Enum.find(socket.assigns.contacts, &(&1.id == contact_id))

    if contact do
      socket = assign(socket,
        loading: true,
        selected_contact: contact,
        error: nil,
        dropdown_open: false,
        query: "",
        suggestions: []
      )
      send(self(), {:generate_salesforce_suggestions, contact, socket.assigns.meeting, socket.assigns.credential})
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
       error: nil
     )}
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

    send(self(), {:apply_salesforce_updates, updates, socket.assigns.selected_contact, socket.assigns.credential})
    {:noreply, socket}
  end

  @impl true
  def handle_event("apply_updates", _params, socket) do
    {:noreply, assign(socket, error: "Please select at least one field to update")}
  end
end
```

**Step 2: Run tests**

Run: `mix test`
Expected: All pass (component compiles)

**Step 3: Commit**

```bash
git add lib/social_scribe_web/live/meeting_live/salesforce_modal_component.ex
git commit -m "feat: add SalesforceModalComponent for contact search and AI suggestions"
```

---

### Task 14: Integrate into MeetingLive.Show + Router

**Files:**
- Modify: `lib/social_scribe_web/live/meeting_live/show.ex`
- Modify: `lib/social_scribe_web/live/meeting_live/show.html.heex`
- Modify: `lib/social_scribe_web/router.ex`

**Step 1: Add route**

In `lib/social_scribe_web/router.ex`, add after the HubSpot route:
```elixir
live "/meetings/:id/salesforce", MeetingLive.Show, :salesforce
```

**Step 2: Update show.ex**

In `lib/social_scribe_web/live/meeting_live/show.ex`:

Add imports/aliases at top:
```elixir
import SocialScribeWeb.ModalComponents, only: [hubspot_modal: 1, salesforce_modal: 1]

alias SocialScribe.SalesforceApiBehaviour, as: SalesforceApi
alias SocialScribe.SalesforceSuggestions
```

In mount, add a nil default for the credential (NO DB query in mount — mount is called twice):
```elixir
|> assign(:salesforce_credential, nil)
```

In `handle_params` catch-all clause, load both credentials (moved from mount per Task 5):
```elixir
def handle_params(_params, _uri, socket) do
  hubspot_credential = Accounts.get_user_hubspot_credential(socket.assigns.current_user.id)
  salesforce_credential = Accounts.get_user_salesforce_credential(socket.assigns.current_user.id)

  {:noreply,
   socket
   |> assign(:hubspot_credential, hubspot_credential)
   |> assign(:salesforce_credential, salesforce_credential)}
end
```

Add 3 new `handle_info` clauses:

```elixir
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
end

@impl true
def handle_info({:generate_salesforce_suggestions, contact, meeting, _credential}, socket) do
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
        error: "Failed to generate suggestions: #{inspect(reason)}",
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
        |> put_flash(:info, "Successfully updated #{map_size(updates)} field(s) in Salesforce")
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
```

**Step 3: Update show.html.heex**

After the HubSpot integration section (line 110), add Salesforce section:

```heex
<div :if={@salesforce_credential} class="bg-white shadow-xl rounded-lg p-6 md:p-8">
  <div class="flex justify-between items-center">
    <div>
      <h2 class="text-2xl font-semibold text-slate-700">Salesforce Integration</h2>
      <p class="text-sm text-slate-500 mt-1">
        Update CRM contacts with information from this meeting
      </p>
    </div>
    <.link
      patch={~p"/dashboard/meetings/#{@meeting}/salesforce"}
      class="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 transition-colors"
    >
      <svg class="w-5 h-5 mr-2" fill="currentColor" viewBox="0 0 24 24">
        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z" />
      </svg>
      Update Salesforce Contact
    </.link>
  </div>
</div>
```

At the end of the template (after the hubspot_modal block), add:

```heex
<.salesforce_modal
  :if={@live_action == :salesforce && @salesforce_credential}
  id="salesforce-modal-wrapper"
  show
  on_cancel={JS.patch(~p"/dashboard/meetings/#{@meeting}")}
>
  <.live_component
    module={SocialScribeWeb.MeetingLive.SalesforceModalComponent}
    id="salesforce-modal"
    meeting={@meeting}
    credential={@salesforce_credential}
    modal_id="salesforce-modal-wrapper"
  />
</.salesforce_modal>
```

**Step 4: Run tests**

Run: `mix test`
Expected: All pass

**Step 5: Commit**

```bash
git add lib/social_scribe_web/live/meeting_live/show.ex lib/social_scribe_web/live/meeting_live/show.html.heex lib/social_scribe_web/router.ex
git commit -m "feat: integrate Salesforce modal into meeting show page with route"
```

---

## Phase 8: Tests

### Task 15: Comprehensive Salesforce tests

**Files:**
- Create: `test/social_scribe_web/controllers/salesforce_auth_test.exs`
- Create: `test/social_scribe_web/live/salesforce_modal_test.exs`
- Create: `test/social_scribe_web/live/salesforce_modal_mox_test.exs`
- Create: `test/social_scribe/salesforce_suggestions_property_test.exs`
- Modify: `test/social_scribe_web/live/user_settings_live_test.exs`

**Step 0: Create auth controller test**

Create `test/social_scribe_web/controllers/salesforce_auth_test.exs`:

```elixir
defmodule SocialScribeWeb.SalesforceAuthTest do
  use SocialScribeWeb.ConnCase

  import SocialScribe.AccountsFixtures

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

      conn =
        conn
        |> assign(:ueberauth_auth, auth)
        |> assign(:current_user, user)
        |> get(~p"/auth/salesforce/callback", %{"provider" => "salesforce"})

      assert redirected_to(conn) == ~p"/dashboard/settings"
      assert get_flash(conn, :info) =~ "Salesforce"

      credential = SocialScribe.Accounts.get_user_salesforce_credential(user.id)
      assert credential.provider == "salesforce"
      assert credential.token == "sf_access_token"
      assert credential.instance_url == "https://na1.salesforce.com"
    end
  end
end
```

**Step 1: Create modal integration test**

Create `test/social_scribe_web/live/salesforce_modal_test.exs`:

```elixir
defmodule SocialScribeWeb.SalesforceModalTest do
  use SocialScribeWeb.ConnCase

  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.BotsFixtures

  setup :register_and_log_in_user

  defp create_meeting_for_user(user) do
    event = calendar_event_fixture(%{user_id: user.id})
    bot = recall_bot_fixture(%{calendar_event_id: event.id})
    meeting = meeting_fixture(%{recall_bot_id: bot.id})
    meeting_transcript_fixture(%{meeting_id: meeting.id})
    meeting
  end

  describe "Salesforce modal" do
    test "shows Salesforce section when credential exists", %{conn: conn, user: user} do
      meeting = create_meeting_for_user(user)
      _credential = salesforce_credential_fixture(%{user_id: user.id})

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")
      assert has_element?(view, "h2", "Salesforce Integration")
      assert has_element?(view, "a", "Update Salesforce Contact")
    end

    test "does not show Salesforce section when no credential", %{conn: conn, user: user} do
      meeting = create_meeting_for_user(user)

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}")
      refute has_element?(view, "h2", "Salesforce Integration")
    end

    test "renders modal when navigating to salesforce route", %{conn: conn, user: user} do
      meeting = create_meeting_for_user(user)
      _credential = salesforce_credential_fixture(%{user_id: user.id})

      {:ok, view, _html} = live(conn, ~p"/dashboard/meetings/#{meeting.id}/salesforce")
      assert has_element?(view, "#salesforce-modal-wrapper")
      assert has_element?(view, "h2", "Update in Salesforce")
    end
  end
end
```

**Step 2: Create Mox integration test**

Create `test/social_scribe_web/live/salesforce_modal_mox_test.exs`:

```elixir
defmodule SocialScribeWeb.SalesforceModalMoxTest do
  use SocialScribeWeb.ConnCase

  import Mox
  import SocialScribe.AccountsFixtures
  import SocialScribe.MeetingsFixtures
  import SocialScribe.CalendarFixtures
  import SocialScribe.BotsFixtures

  setup :verify_on_exit!
  setup :register_and_log_in_user

  defp create_meeting_for_user(user) do
    event = calendar_event_fixture(%{user_id: user.id})
    bot = recall_bot_fixture(%{calendar_event_id: event.id})
    meeting = meeting_fixture(%{recall_bot_id: bot.id})
    meeting_transcript_fixture(%{meeting_id: meeting.id})
    meeting
  end

  describe "behaviour delegation" do
    test "search_contacts delegates to implementation" do
      credential = salesforce_credential_fixture()
      expected = [%{id: "003xx", firstname: "John", lastname: "Doe", email: "john@test.com"}]

      SocialScribe.SalesforceApiMock
      |> expect(:search_contacts, fn _cred, query ->
        assert query == "test query"
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.search_contacts(credential, "test query")
    end

    test "get_contact delegates to implementation" do
      credential = salesforce_credential_fixture()
      expected = %{id: "003xx", firstname: "John", lastname: "Doe"}

      SocialScribe.SalesforceApiMock
      |> expect(:get_contact, fn _cred, id ->
        assert id == "003xx"
        {:ok, expected}
      end)

      assert {:ok, ^expected} =
               SocialScribe.SalesforceApiBehaviour.get_contact(credential, "003xx")
    end

    test "update_contact delegates to implementation" do
      credential = salesforce_credential_fixture()

      SocialScribe.SalesforceApiMock
      |> expect(:update_contact, fn _cred, id, updates ->
        assert id == "003xx"
        assert updates == %{"Phone" => "555-1234"}
        {:ok, :updated}
      end)

      assert {:ok, :updated} =
               SocialScribe.SalesforceApiBehaviour.update_contact(
                 credential,
                 "003xx",
                 %{"Phone" => "555-1234"}
               )
    end
  end
end
```

**Step 3: Create property tests**

Create `test/social_scribe/salesforce_suggestions_property_test.exs`:

```elixir
defmodule SocialScribe.SalesforceSuggestionsPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias SocialScribe.SalesforceSuggestions

  @salesforce_fields ~w(FirstName LastName Email Phone MobilePhone Title Department MailingStreet MailingCity MailingState MailingPostalCode MailingCountry)

  defp suggestion_generator do
    gen all field <- member_of(@salesforce_fields),
            value <- string(:alphanumeric, min_length: 1, max_length: 50),
            context <- string(:alphanumeric, min_length: 1, max_length: 100) do
      %{
        field: field,
        label: field,
        category: "Test Category",
        current_value: nil,
        new_value: value,
        context: context,
        timestamp: "01:00",
        apply: true,
        has_change: true
      }
    end
  end

  defp contact_generator do
    gen all firstname <- string(:alphanumeric, min_length: 1, max_length: 20),
            lastname <- string(:alphanumeric, min_length: 1, max_length: 20),
            email <- string(:alphanumeric, min_length: 1, max_length: 30) do
      %{
        id: "003xx",
        firstname: firstname,
        lastname: lastname,
        email: email,
        phone: nil,
        mobilephone: nil,
        jobtitle: nil,
        department: nil,
        address: nil,
        city: nil,
        state: nil,
        zip: nil,
        country: nil,
        company: nil,
        display_name: "#{firstname} #{lastname}"
      }
    end
  end

  property "all returned suggestions have has_change set to true" do
    check all suggestions <- list_of(suggestion_generator(), min_length: 0, max_length: 10),
              contact <- contact_generator() do
      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      for suggestion <- result do
        assert suggestion.has_change == true
      end
    end
  end

  property "all returned suggestions have apply set to true" do
    check all suggestions <- list_of(suggestion_generator(), min_length: 0, max_length: 10),
              contact <- contact_generator() do
      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)

      for suggestion <- result do
        assert suggestion.apply == true
      end
    end
  end

  property "output length is always <= input length" do
    check all suggestions <- list_of(suggestion_generator(), min_length: 0, max_length: 10),
              contact <- contact_generator() do
      result = SalesforceSuggestions.merge_with_contact(suggestions, contact)
      assert length(result) <= length(suggestions)
    end
  end

  property "empty suggestions returns empty list" do
    check all contact <- contact_generator() do
      assert SalesforceSuggestions.merge_with_contact([], contact) == []
    end
  end
end
```

**Step 4: Add settings test**

In `test/social_scribe_web/live/user_settings_live_test.exs`, add:

```elixir
test "displays connected Salesforce accounts", %{conn: conn, user: user} do
  _credential =
    salesforce_credential_fixture(%{
      user_id: user.id,
      uid: "salesforce-org-123",
      email: "sf_user@example.com"
    })

  {:ok, view, _html} = live(conn, ~p"/dashboard/settings")
  assert has_element?(view, "li", "UID: salesforce-org-123")
end

test "shows Connect Salesforce link", %{conn: conn} do
  {:ok, view, _html} = live(conn, ~p"/dashboard/settings")
  assert has_element?(view, "a", "Connect Salesforce")
end
```

**Step 5: Run all tests**

Run: `mix test`
Expected: All pass

**Step 6: Commit**

```bash
git add test/social_scribe_web/controllers/salesforce_auth_test.exs test/social_scribe_web/live/salesforce_modal_test.exs test/social_scribe_web/live/salesforce_modal_mox_test.exs test/social_scribe/salesforce_suggestions_property_test.exs test/social_scribe_web/live/user_settings_live_test.exs
git commit -m "test: add comprehensive Salesforce integration tests including auth controller and property tests"
```

---

## Phase 9: Documentation

### Task 16: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

Update the following sections:

1. **Environment Variables** — Add `SALESFORCE_CLIENT_ID`, `SALESFORCE_CLIENT_SECRET`
2. **Architecture diagram** — Add `SalesforceApi · SalesforceSuggestions` to External API Layer
3. **External API Layer table** — Add `SalesforceApiBehaviour | SalesforceApi | Salesforce CRM REST v62.0 | Tesla | Bearer token (OAuth) + auto-refresh on 401`
4. **Oban Workers table** — Add `SalesforceTokenRefresher | :default | Cron */30 * * * * | Refreshes Salesforce tokens expiring within 60 minutes`
5. **Routing** — Add `/dashboard/meetings/:id/salesforce MeetingLive.Show, :salesforce`
6. **Salesforce section** — Update from "(Planned)" to completed, with architecture details
7. **Test Infrastructure** — Add `SalesforceApiMock` to Mox definitions, add `salesforce_credential_fixture` to fixtures

**Commit:**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with completed Salesforce integration"
```

---

## Final Verification

Run in order:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix test test/social_scribe/salesforce_api_test.exs test/social_scribe/salesforce_suggestions_test.exs test/social_scribe/salesforce_suggestions_property_test.exs test/social_scribe/salesforce_token_refresher_test.exs test/social_scribe_web/live/salesforce_modal_test.exs test/social_scribe_web/live/salesforce_modal_mox_test.exs test/social_scribe_web/controllers/salesforce_auth_test.exs
```

All must pass with zero warnings.

---

## Files Summary

### New Files (15)

| File | Purpose |
|------|---------|
| `priv/repo/migrations/*_add_instance_url.exs` | Migration for instance_url |
| `lib/ueberauth/strategy/salesforce.ex` | Ueberauth strategy |
| `lib/ueberauth/strategy/salesforce/oauth.ex` | OAuth2 client |
| `lib/social_scribe/salesforce_api_behaviour.ex` | API behaviour + facade |
| `lib/social_scribe/salesforce_api.ex` | Salesforce REST API client |
| `lib/social_scribe/salesforce_token_refresher.ex` | Token refresh logic |
| `lib/social_scribe/workers/salesforce_token_refresher.ex` | Oban cron worker |
| `lib/social_scribe/salesforce_suggestions.ex` | AI suggestion generation |
| `lib/social_scribe_web/live/meeting_live/salesforce_modal_component.ex` | LiveView modal |
| `test/social_scribe/salesforce_api_test.exs` | API unit tests |
| `test/social_scribe/salesforce_suggestions_test.exs` | Suggestion unit tests |
| `test/social_scribe/salesforce_suggestions_property_test.exs` | Property tests |
| `test/social_scribe/salesforce_token_refresher_test.exs` | Token refresh tests |
| `test/social_scribe_web/controllers/salesforce_auth_test.exs` | Auth controller tests |
| `test/social_scribe_web/live/salesforce_modal_test.exs` | LiveView integration tests |
| `test/social_scribe_web/live/salesforce_modal_mox_test.exs` | Mox delegation tests |

### Modified Files (16)

| File | Change |
|------|--------|
| `lib/social_scribe/accounts/user_credential.ex` | Add `instance_url` field |
| `lib/social_scribe/accounts.ex` | Add Salesforce credential functions |
| `lib/social_scribe/ai_content_generator_api.ex` | Add `generate_salesforce_suggestions` callback |
| `lib/social_scribe/ai_content_generator.ex` | Implement Salesforce AI suggestion generation |
| `lib/social_scribe_web/controllers/auth_controller.ex` | Add Salesforce OAuth callback |
| `lib/social_scribe_web/router.ex` | Add `/meetings/:id/salesforce` route |
| `lib/social_scribe_web/live/meeting_live/show.ex` | Add Salesforce credential, handle_info handlers |
| `lib/social_scribe_web/live/meeting_live/show.html.heex` | Add Salesforce button + modal |
| `lib/social_scribe_web/live/user_settings_live.ex` | Add Salesforce accounts assign |
| `lib/social_scribe_web/live/user_settings_live.html.heex` | Add Salesforce connection UI |
| `lib/social_scribe_web/components/modal_components.ex` | Add `salesforce_modal` component |
| `assets/tailwind.config.js` | Add Salesforce color palette |
| `config/config.exs` | Add Salesforce to Ueberauth + Oban cron |
| `config/runtime.exs` | Add Salesforce env vars |
| `config/test.exs` | Add Salesforce test config |
| `test/test_helper.exs` | Add SalesforceApiMock |
| `test/support/fixtures/accounts_fixtures.ex` | Add salesforce_credential_fixture |
| `test/social_scribe_web/live/user_settings_live_test.exs` | Add Salesforce settings tests |
| `lib/social_scribe_web/live/meeting_live/hubspot_modal_component.ex` | Pass theme prop to shared components |
| `CLAUDE.md` | Update with Salesforce architecture |
