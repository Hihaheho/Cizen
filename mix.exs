defmodule Cizen.MixProject do
  use Mix.Project

  def project do
    [
      app: :cizen,
      version: "0.1.0",
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      start_phases: [start_children: [], start_daemons: []],
      extra_applications: [:logger],
      mod: {Cizen.Application, []}
    ]
  end

  defp deps do
    [
      {:elixir_uuid, "~> 1.2"},
      {:poison, "~> 4.0", only: [:test]},
      {:credo, "~> 0.10.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0.0-rc.3", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.8", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      credo: ["credo --strict"],
      check: [
        "compile --warnings-as-errors",
        "format --check-formatted --check-equivalent",
        "credo --strict",
        "dialyzer --no-compile --halt-exit-status"
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
