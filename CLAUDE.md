# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Social Scribe is an Elixir/Phoenix LiveView application that automates post-meeting workflows for **financial advisors**. After an advisor meets with a client, the app uses the meeting transcript and AI to generate follow-up items: a recap email, social media content via user-defined automations, and AI-suggested updates to the client's CRM contact record.

**Core workflow:** Advisor connects Google Calendar → app sends AI notetaker (Recall.ai) to client meetings → transcribes → Gemini AI generates follow-up email + automation content + CRM update suggestions (HubSpot, Salesforce).

**Tech stack:** Elixir 1.17+, Phoenix 1.7 (LiveView), PostgreSQL, Oban (background jobs), Tesla (HTTP), Ueberauth (OAuth), Tailwind CSS, Heroicons.

## Commands

```bash
# Setup & Server
mix setup                          # deps.get + ecto.setup + assets.setup + assets.build
source .env && mix phx.server      # Start dev server (env vars required)
iex -S mix phx.server              # Start with IEx shell

# Database
mix ecto.migrate                   # Run pending migrations
mix ecto.reset                     # Drop + create + migrate + seed
mix ecto.rollback                  # Roll back last migration

# Testing
mix test                           # All tests (auto-creates/migrates test DB)
mix test test/social_scribe/hubspot_api_test.exs        # Single file
mix test test/social_scribe/hubspot_api_test.exs:42     # Single test by line
mix test --only property           # Property-based tests (if tagged)

# Code Quality
mix format                         # Format .ex, .exs, .heex files
mix format --check-formatted       # CI format check
```

## Environment Variables

All configured in `config/runtime.exs`. Create a `.env` file and `source .env` before running:

```
GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REDIRECT_URI
RECALL_API_KEY, RECALL_REGION
GEMINI_API_KEY
LINKEDIN_CLIENT_ID, LINKEDIN_CLIENT_SECRET, LINKEDIN_REDIRECT_URI
FACEBOOK_CLIENT_ID, FACEBOOK_CLIENT_SECRET, FACEBOOK_REDIRECT_URI
HUBSPOT_CLIENT_ID, HUBSPOT_CLIENT_SECRET
SALESFORCE_CLIENT_ID, SALESFORCE_CLIENT_SECRET
```

Production additionally requires: `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, `PHX_SERVER=true`.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        Web Layer (LiveView)                     │
│  HomeLive · MeetingLive · AutomationLive · UserSettingsLive     │
│  AuthController · UserSessionController                         │
├─────────────────────────────────────────────────────────────────┤
│                     Context Layer (Business Logic)               │
│  Accounts · Calendar · Bots · Meetings · Automations            │
│  CalendarSyncronizer · Poster                                   │
├─────────────────────────────────────────────────────────────────┤
│                   External API Layer (Behaviours)                │
│  GoogleCalendarApi · RecallApi · AIContentGeneratorApi           │
│  TokenRefresherApi · HubspotApiBehaviour                        │
│  LinkedInApi · FacebookApi · SalesforceApiBehaviour              │
│  SalesforceApi · SalesforceSuggestions                           │
├─────────────────────────────────────────────────────────────────┤
│                    Background Workers (Oban)                     │
│  BotStatusPoller · AIContentGenerationWorker                    │
│  HubspotTokenRefresher · SalesforceTokenRefresher               │
├─────────────────────────────────────────────────────────────────┤
│                    Data Layer (Ecto + PostgreSQL)                │
│  12 schemas across 5 contexts                                   │
└─────────────────────────────────────────────────────────────────┘
```

## Core Data Flow

The primary pipeline is event-driven via Oban:

```
Advisor connects Google Calendar → CalendarEvent (DB)
Advisor toggles "Record" on client meeting → RecallBot created via Recall.ai API
  ↓ (every 2 min cron)
BotStatusPoller polls Recall.ai → bot status == "done"
  → Creates Meeting + MeetingTranscript + MeetingParticipants (in transaction)
  → Enqueues AIContentGenerationWorker
    → Gemini generates follow-up email → updates Meeting.follow_up_email
    → For each active Automation → Gemini generates content → creates AutomationResult
Advisor views Meeting → can post to LinkedIn/Facebook via Poster
                      → can open HubSpot modal → AI suggests CRM contact updates
                      → can open Salesforce modal → AI suggests CRM contact updates
```

## Context Modules

All business logic lives in `lib/social_scribe/` as Phoenix contexts.

### Accounts (`accounts.ex`)
User registration (password + OAuth), session tokens, multi-provider OAuth credential storage (Google, LinkedIn, Facebook, HubSpot, Salesforce), Facebook page credential management. Key functions:
- `find_or_create_user_from_oauth/1` — handles initial login (creates user + credential in transaction)
- `find_or_create_user_credential/2` — upserts credential for logged-in users (links additional OAuth accounts)
- `find_or_create_hubspot_credential/2` — HubSpot-specific credential upsert
- `find_or_create_salesforce_credential/2` — Salesforce-specific credential upsert (includes `instance_url`)
- `get_user_salesforce_credential/1` — fetches user's Salesforce credential
- `update_credential_tokens/2` — refreshes access tokens on stored credentials
- `link_facebook_page/3` — creates/updates Facebook page credentials

### Calendar (`calendar.ex`)
CRUD for synced Google Calendar events. Uses upsert on `[:user_id, :google_event_id]` conflict.
- `list_upcoming_events/1` — filters by user_id where start_time > now, ordered ascending

### CalendarSyncronizer (`calendar_syncronizer.ex`)
Orchestrates Google Calendar → DB sync. Uses `Task.async_stream` to parallelize across multiple Google credentials. Filters events to only those with Zoom/Google Meet links (hangout_link or location). Handles token refresh transparently.

### Bots (`bots.ex`)
Manages Recall.ai bot lifecycle and user bot preferences.
- `create_and_dispatch_bot/2` — creates bot via Recall.ai API + saves to DB (uses UserBotPreference for join_minute_offset)
- `cancel_and_delete_bot/1` — deletes from API + DB
- `list_pending_bots/0` — bots with status not in `["done", "error", "polling_error"]`

### Meetings (`meetings.ex`)
Creates complete meeting records from Recall.ai response data.
- `create_meeting_from_recall_data/4` — transaction inserting Meeting + MeetingTranscript + MeetingParticipants
- `generate_prompt_for_meeting/1` — formats meeting data (title, participants, formatted transcript with timestamps) as a prompt string for Gemini
- `list_user_meetings/1` — joins through recall_bot → calendar_event → user, preloads transcript/participants

### Automations (`automations.ex`)
User-defined prompt templates with platform targeting. Enforces max 1 active automation per platform per user.
- `can_create_automation?/2` and `can_update_automation?/3` — validate platform uniqueness constraint
- `generate_prompt_for_automation/1` — combines description + example for AI prompt
- `list_automation_results_for_meeting/1` — preloads automation on each result

### Poster (`poster.ex`)
Dispatches social media posts to LinkedIn or Facebook. Reads credentials from Accounts context, calls the respective API.

## External API Layer — Behaviour Pattern

All external service calls use a **behaviour + facade + Mox** pattern:

```elixir
# Behaviour module defines callbacks AND delegates to runtime implementation:
defmodule SocialScribe.RecallApi do
  @callback create_bot(String.t(), DateTime.t()) :: {:ok, Tesla.Env.t()} | {:error, any()}
  # ... more callbacks

  def create_bot(url, join_at), do: impl().create_bot(url, join_at)

  defp impl, do: Application.get_env(:social_scribe, :recall_api, SocialScribe.Recall)
end
```

In tests, mocks are injected in `test/test_helper.exs`:
```elixir
Mox.defmock(SocialScribe.RecallApiMock, for: SocialScribe.RecallApi)
Application.put_env(:social_scribe, :recall_api, SocialScribe.RecallApiMock)
```

| Behaviour/Facade | Default Impl | Service | HTTP Client | Auth Method |
|---|---|---|---|---|
| `GoogleCalendarApi` | `GoogleCalendar` | Google Calendar API | Tesla | Bearer token (OAuth) |
| `RecallApi` | `Recall` | Recall.ai v1 | Tesla | `Token` header (API key) |
| `AIContentGeneratorApi` | `AIContentGenerator` | Google Gemini (gemini-2.0-flash-lite) | Tesla | Query param `?key=` |
| `TokenRefresherApi` | `TokenRefresher` | Google OAuth2 token endpoint | Tesla | OAuth2 refresh grant |
| `HubspotApiBehaviour` | `HubspotApi` | HubSpot CRM v3 | Tesla | Bearer token (OAuth) + auto-refresh on 401 |
| `SalesforceApiBehaviour` | `SalesforceApi` | Salesforce CRM REST v62.0 | Tesla | Bearer token (OAuth) + auto-refresh on 401 |

**Non-behaviour APIs** (no Mox mock, called directly):
- `LinkedInApi` / `LinkedIn` — LinkedIn v2 API, Bearer token, posts text shares
- `FacebookApi` / `Facebook` — Facebook Graph API v22.0, page access token, posts to pages + fetches user pages

### CRM Integrations

#### HubSpot (Complete)

HubSpot has the most sophisticated integration and serves as the **reference pattern for adding new CRM integrations** (e.g., Salesforce):
- **Custom Ueberauth strategy** (`lib/ueberauth/strategy/hubspot.ex` + `hubspot/oauth.ex`) — OAuth2 flow with HubSpot-specific endpoints
- **Automatic token refresh** — `HubspotApi` retries on 401 by refreshing the token then re-calling the API
- **Proactive refresh** — `Workers.HubspotTokenRefresher` cron worker refreshes tokens expiring within 10 minutes
- **AI suggestions** — `HubspotSuggestions.generate_suggestions/3` fetches contact from HubSpot, sends transcript to Gemini, merges AI suggestions with current contact values
- **UI modal** — `HubspotModalComponent` is a multi-step live component (`:search` → `:suggestions`) with contact search, AI suggestion cards with checkboxes, selective field updates
- **Reusable UI components** — `ModalComponents` module has CRM-agnostic components: `crm_modal`, `contact_select`, `suggestion_card`, `suggestion_group`, `avatar`, `modal_footer`, `empty_state`, `inline_error`

#### Salesforce (Complete)

Follows the same architecture pattern as HubSpot:
- **Custom Ueberauth strategy** (`lib/ueberauth/strategy/salesforce.ex` + `salesforce/oauth.ex`) — OAuth2 flow with Salesforce-specific endpoints, dynamic `instance_url` extraction
- **Automatic token refresh** — `SalesforceApi` wraps all calls with `with_token_refresh/2`, retries on 401 by refreshing via `SalesforceTokenRefresher`
- **Proactive refresh** — `Workers.SalesforceTokenRefresher` cron worker (every 30 min) refreshes tokens expiring within 60 minutes
- **AI suggestions** — `SalesforceSuggestions.generate_suggestions_from_meeting/1` sends transcript to Gemini, `merge_with_contact/2` overlays current contact values and filters unchanged fields
- **UI modal** — `SalesforceModalComponent` is a multi-step live component (`:search` → `:suggestions`) with contact search, AI suggestion cards grouped by category, selective field updates
- **Reusable UI components** — shares `ModalComponents` with HubSpot via `theme` prop for color switching
- **Schema** — `UserCredential` has `instance_url` field for Salesforce's per-org API endpoint
- **Field mappings** — PascalCase Salesforce fields (FirstName, MailingCity, etc.) mapped to atom keys matching `SalesforceApi.format_contact/1`

## Oban Workers

Configured in `config/config.exs`. Queues: `default: 10`, `ai_content: 10`, `polling: 5`.

| Worker | Queue | Trigger | What it does |
|---|---|---|---|
| `BotStatusPoller` | `:polling` | Cron `*/2 * * * *` | Polls pending Recall.ai bots, updates status, creates meetings when "done", enqueues AI generation |
| `AIContentGenerationWorker` | `:ai_content` | On-demand (from BotStatusPoller) | Generates follow-up email + processes all active automations via Gemini |
| `HubspotTokenRefresher` | `:default` | Cron `*/5 * * * *` | Refreshes HubSpot tokens expiring within 10 minutes |
| `SalesforceTokenRefresher` | `:default` | Cron `*/30 * * * *` | Refreshes Salesforce tokens expiring within 60 minutes |

All workers have `max_attempts: 3`. Oban test mode: `:manual` (use `Oban.Testing` in DataCase).

## Web Layer

### Routing

All authenticated routes are under `/dashboard` with `:dashboard` layout:
```
/                           LandingLive (public)
/auth/:provider             AuthController :request (Ueberauth redirect)
/auth/:provider/callback    AuthController :callback (OAuth callback)
/dashboard                  HomeLive (calendar events, bot toggle)
/dashboard/settings         UserSettingsLive (OAuth connections, bot preferences)
/dashboard/meetings         MeetingLive.Index (past meetings list)
/dashboard/meetings/:id     MeetingLive.Show (transcript, email, posts, HubSpot, Salesforce)
/dashboard/meetings/:id/salesforce  MeetingLive.Show :salesforce (Salesforce modal)
/dashboard/automations      AutomationLive.Index (CRUD automations)
/dashboard/automations/:id  AutomationLive.Show (automation detail)
```

Dev-only routes: `/oban` (Oban Web), `/dev/dashboard` (LiveDashboard), `/dev/mailbox` (Swoosh).

### LiveView Authentication

Two `on_mount` hooks on all `/dashboard` routes:
1. `{SocialScribeWeb.UserAuth, :ensure_authenticated}` — redirects to `/` if no session
2. `{SocialScribeWeb.LiveHooks, :assign_current_path}` — tracks current URI path for sidebar active state

### LiveView Patterns

- **Async work in LiveView:** HomeLive sends `:sync_calendars` to self on mount (when connected), handles in `handle_info`
- **Component communication:** HubspotModalComponent sends async messages to parent (MeetingLive.Show), parent processes and calls `send_update/2` back to component
- **Form pattern:** `to_form()` with `:validate` action for real-time validation
- **Authorization:** MeetingLive.Show checks meeting ownership inline in mount, redirects with flash on failure

### AuthController OAuth Callbacks

`AuthController.callback/2` handles all 5 providers differently:
- **Google/LinkedIn (logged-in):** Upserts credential, redirects to `/dashboard/settings`
- **Facebook (logged-in):** Upserts credential, fetches user pages via `FacebookApi.fetch_user_pages`, links each page, redirects to `/dashboard/settings/facebook_pages`
- **HubSpot (logged-in):** Extracts hub_id/token/refresh_token, creates credential, redirects to `/dashboard/settings`
- **Salesforce (logged-in):** Extracts org_id/token/refresh_token/instance_url, validates instance_url presence, creates credential, redirects to `/dashboard/settings`
- **Any provider (not logged in):** Creates user + credential via `find_or_create_user_from_oauth`, logs in

### Components

- `Sidebar` — navigation with active state detection from `:current_path` assign
- `ModalComponents` — reusable CRM modal UI: `crm_modal`, `contact_select`, `suggestion_card`, `suggestion_group`, `avatar`, `modal_footer`, `empty_state`, `inline_error` (shared components use `theme` prop for HubSpot/Salesforce color switching)
- `ClipboardButton` — live component using JS hook for clipboard copy with visual feedback
- `PlatformLogo` — detects Google Meet vs Zoom from meeting URL

### JS Hooks

Single hook in `assets/js/hooks.js`:
- `Clipboard` — handles `copy-to-clipboard` event, writes to `navigator.clipboard`, sends confirmation back, auto-resets after 2 seconds

## Data Model

### Entity Relationship Diagram

```
User (advisor)
 ├── has_many UserCredential (provider: google|linkedin|facebook|hubspot|salesforce)
 │    └── has_many FacebookPageCredential (selected: boolean, unique per user)
 ├── has_many CalendarEvent (via user_id, no belongs_to in schema)
 │    ├── has_one RecallBot (recall_bot_id, status, meeting_url)
 │    │    └── has_one Meeting (client meeting record)
 │    │         ├── has_one MeetingTranscript (content: map, language)
 │    │         ├── has_many MeetingParticipant (name, is_host)
 │    │         └── has_many AutomationResult (via automation_id + meeting_id)
 │    └── (record_meeting: boolean toggle)
 ├── has_many Automation (name, platform: :linkedin|:facebook, description, example, is_active)
 │    └── has_many AutomationResult (status, generated_content, error_message)
 └── has_one UserBotPreference (join_minute_offset: 0..10, default 2)
 └── UserToken (session tokens)
```

### Key Schema Details

- **CalendarEvent** uses raw `:id` fields for `user_id`/`user_credential_id` (no `belongs_to` in schema)
- **Automation.platform** is an `Ecto.Enum` with values `[:linkedin, :facebook]`
- **MeetingTranscript.content** is a `:map` field storing the full Recall.ai transcript JSON
- **FacebookPageCredential** has unique constraint on `facebook_page_id` and on `[user_id, selected]` (only one selected page per user)
- **RecallBot** has unique constraint on `recall_bot_id`
- **UserBotPreference** has unique constraint on `user_id`, validates `join_minute_offset` in 0..10

## Testing

### Test Infrastructure

- **Mox** for all external API mocks — 6 mocks defined in `test/test_helper.exs`:
  - `GoogleCalendarApiMock`, `TokenRefresherMock`, `RecallApiMock`, `AIContentGeneratorMock`, `HubspotApiMock`, `SalesforceApiMock`
- **Oban.Testing** with `:manual` mode — available via `use Oban.Testing, repo: SocialScribe.Repo` in DataCase
- **Ecto.Adapters.SQL.Sandbox** in `:manual` mode for test isolation

### Test Cases

- `DataCase` — for context tests: imports Ecto, Oban.Testing, provides `errors_on/1` helper
- `ConnCase` — for controller/LiveView tests: provides `register_and_log_in_user` setup, `log_in_user/2` helper

### Fixtures

All in `test/support/fixtures/`:
- `AccountsFixtures` — `user_fixture`, `user_credential_fixture`, `hubspot_credential_fixture`, `salesforce_credential_fixture`, `facebook_page_credential_fixture`
- `AutomationsFixtures` — `automation_fixture`, `automation_result_fixture`
- `BotsFixtures` — `recall_bot_fixture`, `user_bot_preference_fixture`
- `CalendarFixtures` — `calendar_event_fixture`
- `MeetingsFixtures` — `meeting_fixture`, `meeting_transcript_fixture`, `meeting_participant_fixture`

### Example Data

Realistic test data in `test/support/examples/`:
- `MeetingInfoExample` — full Recall.ai bot response with status transitions, recordings, participants
- `MeetingTranscriptExample` — 34 transcript segments with words, timestamps, confidence scores

### Property Tests

Uses `StreamData` for property-based testing (e.g., `hubspot_api_property_test.exs`, `hubspot_suggestions_property_test.exs`, `salesforce_suggestions_property_test.exs`).

## Deployment

Docker multi-stage build (`Dockerfile`):
- Builder: `hexpm/elixir:1.18.3-erlang-27.3.4-debian-bullseye-20250428-slim`
- Runner: `debian:bullseye-20250428-slim`
- Builds Mix release, runs as `nobody` user
- Production config supports Cloud SQL Unix socket connections (parsed from `DATABASE_URL` query params)

## Frontend

- **Tailwind CSS** with custom colors: brand `#FD4F00` (orange), HubSpot palette (greens, blues, grays), Salesforce palette (blues `#0070D2`, grays `#706E6B`)
- **Heroicons** v2.1.1 via dynamic Tailwind components
- **topbar.js** for page loading progress bar
- **esbuild** for JS bundling, **Tailwind** for CSS
- Custom Tailwind variants for Phoenix loading states: `phx-click-loading`, `phx-submit-loading`, `phx-change-loading`
