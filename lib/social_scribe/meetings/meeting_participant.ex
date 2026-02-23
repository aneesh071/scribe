defmodule SocialScribe.Meetings.MeetingParticipant do
  @moduledoc """
  Schema for meeting participants extracted from Recall.ai recordings.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Meetings.Meeting

  @type t :: %__MODULE__{}

  schema "meeting_participants" do
    field :recall_participant_id, :string
    field :name, :string
    field :is_host, :boolean

    belongs_to :meeting, Meeting

    timestamps()
  end

  def changeset(participant, attrs) do
    participant
    |> cast(attrs, [:recall_participant_id, :name, :is_host, :meeting_id])
    |> validate_required([:recall_participant_id, :name, :meeting_id])
  end
end
