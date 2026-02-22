defmodule SocialScribe.Repo do
  @moduledoc """
  The Ecto repository for SocialScribe, backed by PostgreSQL.
  """

  use Ecto.Repo,
    otp_app: :social_scribe,
    adapter: Ecto.Adapters.Postgres
end
