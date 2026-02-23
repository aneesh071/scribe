defmodule SocialScribe.Salesforce.Validation do
  @moduledoc """
  Shared validation helpers for Salesforce integration.

  Provides domain validation for Salesforce instance URLs to prevent SSRF attacks.
  Used by both the OAuth callback (AuthController) and token refresher.
  """

  @salesforce_domain_patterns [
    ~r/\.salesforce\.com$/i,
    ~r/\.force\.com$/i,
    ~r/\.sfdc\.net$/i
  ]

  @doc """
  Returns true if the given URL belongs to a known Salesforce domain.

  Parses the URL and checks the host component against allowed patterns:
  `*.salesforce.com`, `*.force.com`, `*.sfdc.net`.

  ## Examples

      iex> valid_salesforce_domain?("https://na1.salesforce.com")
      true

      iex> valid_salesforce_domain?("https://evil-attacker.com")
      false

      iex> valid_salesforce_domain?(nil)
      false
  """
  @spec valid_salesforce_domain?(any()) :: boolean()
  def valid_salesforce_domain?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: host} when is_binary(host) ->
        Enum.any?(@salesforce_domain_patterns, &Regex.match?(&1, host))

      _ ->
        false
    end
  end

  def valid_salesforce_domain?(_), do: false
end
