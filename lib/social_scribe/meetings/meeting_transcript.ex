defmodule SocialScribe.Meetings.MeetingTranscript do
  @moduledoc """
  Schema for meeting transcripts. Content is stored as a map from the Recall.ai API.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias SocialScribe.Meetings.Meeting

  @type t :: %__MODULE__{}

  schema "meeting_transcripts" do
    field :content, :map
    field :language, :string

    belongs_to :meeting, Meeting

    timestamps()
  end

  def changeset(transcript, attrs) do
    transcript
    |> cast(attrs, [:content, :language, :meeting_id])
    |> validate_required([:content, :meeting_id])
  end
end
