defmodule Lakeland.Mixfile do
  use Mix.Project

  @dialyzer_configs [
  ]

  def project do
    [app: :lakeland,
     version: "0.1.0",
     elixir: "~> 1.2",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps,
     dialyzer: @dialyzer_configs
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger],
     mod: {Lakeland.App, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:earmark, "~> 0.1", only: [:dev]},
      {:ex_doc, "~> 0.11", only: [:dev]},
      {:dialyxir, "~> 0.3", only: [:dev]}
    ]
  end
end
