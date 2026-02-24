defmodule SocialScribe.Bots do
  @moduledoc """
  The Bots context.
  """

  import Ecto.Query, warn: false
  alias SocialScribe.Repo

  require Logger

  alias SocialScribe.Bots.RecallBot
  alias SocialScribe.Bots.UserBotPreference
  alias SocialScribe.RecallApi

  @doc """
  Returns the list of recall_bots.

  ## Examples

      iex> list_recall_bots()
      [%RecallBot{}, ...]

  """
  @spec list_recall_bots() :: [RecallBot.t()]
  def list_recall_bots do
    Repo.all(RecallBot)
  end

  @staleness_hours 24

  @doc """
  Lists all bots whose status is not yet "done" or "error" and were created
  within the last #{@staleness_hours} hours. Prevents indefinite polling of stuck bots.
  """
  @spec list_pending_bots() :: [RecallBot.t()]
  def list_pending_bots do
    cutoff = DateTime.add(DateTime.utc_now(), -@staleness_hours, :hour)

    from(b in RecallBot,
      where: b.status not in ["done", "error", "polling_error"],
      where: b.inserted_at >= ^cutoff
    )
    |> Repo.all()
  end

  @doc """
  Gets a single recall_bot.

  Raises `Ecto.NoResultsError` if the Recall bot does not exist.

  ## Examples

      iex> get_recall_bot!(123)
      %RecallBot{}

      iex> get_recall_bot!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_recall_bot!(integer()) :: RecallBot.t()
  def get_recall_bot!(id), do: Repo.get!(RecallBot, id)

  @doc """
  Creates a recall_bot.

  ## Examples

      iex> create_recall_bot(%{field: value})
      {:ok, %RecallBot{}}

      iex> create_recall_bot(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_recall_bot(map()) :: {:ok, RecallBot.t()} | {:error, Ecto.Changeset.t()}
  def create_recall_bot(attrs \\ %{}) do
    %RecallBot{}
    |> RecallBot.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a recall_bot.

  ## Examples

      iex> update_recall_bot(recall_bot, %{field: new_value})
      {:ok, %RecallBot{}}

      iex> update_recall_bot(recall_bot, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_recall_bot(RecallBot.t(), map()) ::
          {:ok, RecallBot.t()} | {:error, Ecto.Changeset.t()}
  def update_recall_bot(%RecallBot{} = recall_bot, attrs) do
    recall_bot
    |> RecallBot.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a recall_bot.

  ## Examples

      iex> delete_recall_bot(recall_bot)
      {:ok, %RecallBot{}}

      iex> delete_recall_bot(recall_bot)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_recall_bot(RecallBot.t()) ::
          {:ok, RecallBot.t()} | {:error, Ecto.Changeset.t()}
  def delete_recall_bot(%RecallBot{} = recall_bot) do
    Repo.delete(recall_bot)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking recall_bot changes.

  ## Examples

      iex> change_recall_bot(recall_bot)
      %Ecto.Changeset{data: %RecallBot{}}

  """
  @spec change_recall_bot(RecallBot.t(), map()) :: Ecto.Changeset.t()
  def change_recall_bot(%RecallBot{} = recall_bot, attrs \\ %{}) do
    RecallBot.changeset(recall_bot, attrs)
  end

  # --- Orchestration Functions ---

  @doc """
  Orchestrates creating a bot via the API and saving it to the database.
  """
  @spec create_and_dispatch_bot(
          SocialScribe.Accounts.User.t(),
          SocialScribe.Calendar.CalendarEvent.t()
        ) ::
          {:ok, RecallBot.t()} | {:error, Ecto.Changeset.t()} | {:error, {:api_error, any()}}
  def create_and_dispatch_bot(user, calendar_event) do
    user_bot_preference = get_user_bot_preference(user.id) || %UserBotPreference{}
    join_minute_offset = user_bot_preference.join_minute_offset

    with {:ok, %{status: status, body: api_response}} when status in 200..299 <-
           RecallApi.create_bot(
             calendar_event.hangout_link,
             DateTime.add(
               calendar_event.start_time,
               -join_minute_offset,
               :minute
             )
           ),
         %{id: bot_id} <- api_response do
      status = get_in(api_response, [:status_changes, Access.at(0), :code]) || "ready"

      create_recall_bot(%{
        user_id: user.id,
        calendar_event_id: calendar_event.id,
        recall_bot_id: bot_id,
        meeting_url: calendar_event.hangout_link,
        status: status
      })
    else
      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, {status, body}}}

      {:error, reason} ->
        {:error, {:api_error, reason}}

      _ ->
        {:error, {:api_error, :invalid_response}}
    end
  end

  @doc """
  Orchestrates deleting a bot via the API and removing it from the database.
  """
  @spec cancel_and_delete_bot(SocialScribe.Calendar.CalendarEvent.t()) ::
          {:ok, :no_bot_to_cancel}
          | {:ok, RecallBot.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, {:api_error, any()}}
  def cancel_and_delete_bot(calendar_event) do
    case Repo.get_by(RecallBot, calendar_event_id: calendar_event.id) do
      nil ->
        {:ok, :no_bot_to_cancel}

      %RecallBot{} = bot ->
        case RecallApi.delete_bot(bot.recall_bot_id) do
          {:ok, %{status: 404}} -> delete_recall_bot(bot)
          {:ok, _} -> delete_recall_bot(bot)
          {:error, reason} -> {:error, {:api_error, reason}}
        end
    end
  end

  @doc """
  Orchestrates updating a bot's schedule via the API and saving it to the database.
  """
  @spec update_bot_schedule(RecallBot.t(), SocialScribe.Calendar.CalendarEvent.t()) ::
          {:ok, RecallBot.t()} | {:error, Ecto.Changeset.t()} | {:error, any()}
  def update_bot_schedule(bot, calendar_event) do
    user_bot_preference = get_user_bot_preference(bot.user_id) || %UserBotPreference{}
    join_minute_offset = user_bot_preference.join_minute_offset

    with {:ok, %{body: api_response}} <-
           RecallApi.update_bot(
             bot.recall_bot_id,
             calendar_event.hangout_link,
             DateTime.add(calendar_event.start_time, -join_minute_offset, :minute)
           ) do
      status =
        case api_response do
          %{status_changes: [%{code: code} | _]} -> code
          _ -> bot.status
        end

      update_recall_bot(bot, %{status: status})
    end
  end

  @doc """
  Reschedules all pending bots for a user with the current bot preference offset.

  Called when the user updates their join_minute_offset in settings, so that
  already-scheduled bots are updated via the Recall.ai API.
  """
  @spec reschedule_pending_bots_for_user(integer()) :: :ok
  def reschedule_pending_bots_for_user(user_id) do
    pending_bots =
      from(b in RecallBot,
        where: b.user_id == ^user_id,
        where: b.status not in ["done", "error", "polling_error"],
        preload: [:calendar_event]
      )
      |> Repo.all()

    for bot <- pending_bots, bot.calendar_event != nil do
      case update_bot_schedule(bot, bot.calendar_event) do
        {:ok, _} ->
          Logger.info("Rescheduled bot #{bot.recall_bot_id} with updated offset")

        {:error, reason} ->
          Logger.warning("Failed to reschedule bot #{bot.recall_bot_id}: #{inspect(reason)}")
      end
    end

    :ok
  end

  @doc """
  Returns the list of user_bot_preferences.

  ## Examples

      iex> list_user_bot_preferences()
      [%UserBotPreference{}, ...]

  """
  @spec list_user_bot_preferences() :: [UserBotPreference.t()]
  def list_user_bot_preferences do
    Repo.all(UserBotPreference)
  end

  @doc """
  Gets a single user_bot_preference.

  Raises `Ecto.NoResultsError` if the User bot preference does not exist.

  ## Examples

      iex> get_user_bot_preference!(123)
      %UserBotPreference{}

      iex> get_user_bot_preference!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_user_bot_preference!(integer()) :: UserBotPreference.t()
  def get_user_bot_preference!(id), do: Repo.get!(UserBotPreference, id)

  @spec get_user_bot_preference(integer()) :: UserBotPreference.t() | nil
  def get_user_bot_preference(user_id) do
    Repo.get_by(UserBotPreference, user_id: user_id)
  end

  @doc """
  Creates a user_bot_preference.

  ## Examples

      iex> create_user_bot_preference(%{field: value})
      {:ok, %UserBotPreference{}}

      iex> create_user_bot_preference(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_user_bot_preference(map()) ::
          {:ok, UserBotPreference.t()} | {:error, Ecto.Changeset.t()}
  def create_user_bot_preference(attrs \\ %{}) do
    %UserBotPreference{}
    |> UserBotPreference.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a user_bot_preference.

  ## Examples

      iex> update_user_bot_preference(user_bot_preference, %{field: new_value})
      {:ok, %UserBotPreference{}}

      iex> update_user_bot_preference(user_bot_preference, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_user_bot_preference(UserBotPreference.t(), map()) ::
          {:ok, UserBotPreference.t()} | {:error, Ecto.Changeset.t()}
  def update_user_bot_preference(%UserBotPreference{} = user_bot_preference, attrs) do
    user_bot_preference
    |> UserBotPreference.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a user_bot_preference.

  ## Examples

      iex> delete_user_bot_preference(user_bot_preference)
      {:ok, %UserBotPreference{}}

      iex> delete_user_bot_preference(user_bot_preference)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_user_bot_preference(UserBotPreference.t()) ::
          {:ok, UserBotPreference.t()} | {:error, Ecto.Changeset.t()}
  def delete_user_bot_preference(%UserBotPreference{} = user_bot_preference) do
    Repo.delete(user_bot_preference)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user_bot_preference changes.

  ## Examples

      iex> change_user_bot_preference(user_bot_preference)
      %Ecto.Changeset{data: %UserBotPreference{}}

  """
  @spec change_user_bot_preference(UserBotPreference.t(), map()) :: Ecto.Changeset.t()
  def change_user_bot_preference(%UserBotPreference{} = user_bot_preference, attrs \\ %{}) do
    UserBotPreference.changeset(user_bot_preference, attrs)
  end
end
