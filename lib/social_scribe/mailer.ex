defmodule SocialScribe.Mailer do
  @moduledoc """
  The Swoosh mailer for delivering emails from SocialScribe.
  """

  use Swoosh.Mailer, otp_app: :social_scribe
end
