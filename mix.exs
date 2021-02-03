defmodule Cizen.MixProject do
  use Mix.Project

  def project do
    [
      app: :cizen,
      version: "0.16.0",
      package: package(),
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Cizen",
      docs: docs(),
      source_url: "https://gitlab.com/cizen/cizen",
      description: """
      Build highly concurrent, monitorable, and extensible applications with a collection of automata.
      """,
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
      mod: {Cizen.Application, []},
      env: [event_router: Cizen.DefaultEventRouter]
    ]
  end

  defp package do
    [
      links: %{gitlab: "https://gitlab.com/cizen/cizen"},
      licenses: ["MIT"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:recon, "~> 2.5", only: :test},
      {:uuid, "~> 1.1"},
      {:poison, "~> 4.0", only: :test, runtime: false},
      {:credo, "~> 0.10.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0.0-rc.3", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.8", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:mock, "~> 0.3", only: :test}
    ]
  end

  defp docs do
    [
      main: "readme",
      extra_section: "GUIDES",
      groups_for_modules: groups_for_modules(),
      extras: extras(),
      groups_for_extras: groups_for_extras()
    ]
  end

  defp extras do
    [
      {"README.md", [filename: "readme", title: "Read Me"]},
      "guides/getting_started.md",
      "guides/basic_concepts/event.md",
      "guides/basic_concepts/filter.md",
      "guides/basic_concepts/saga.md",
      "guides/basic_concepts/effect.md",
      "guides/basic_concepts/test.md",
      "guides/advanced_concepts/channel.md"
    ]
  end

  defp groups_for_extras do
    [
      Guides: ~r/guides\/[^\/]+\.md/,
      "Basic Concepts": ~r/guides\/basic_concepts\/.?/,
      "Advanced Concepts": ~r/guides\/advanced_concepts\/.?/
    ]
  end

  defp groups_for_modules do
    [
      Automaton: [
        Cizen.Automaton
      ],
      "Automaton Internal": [
        Cizen.Automaton.PerformEffect,
        Cizen.Effect,
        Cizen.EffectHandler
      ],
      Channel: [
        Cizen.Channel,
        Cizen.Channel.EmitMessage,
        Cizen.Channel.FeedMessage,
        Cizen.RegisterChannel,
        Cizen.RegisterChannel.Registered
      ],
      Dispatchers: [
        Cizen.Dispatcher,
        Cizen.FilterDispatcher
      ],
      "Dispatcher Internal": [
        Cizen.DefaultEventRouter,
        Cizen.EventRouter,
        Cizen.FilterDispatcher.PushEvent
      ],
      Effects: [
        Cizen.Effects,
        Cizen.Effects.All,
        Cizen.Effects.Chain,
        Cizen.Effects.Dispatch,
        Cizen.Effects.End,
        Cizen.Effects.Fork,
        Cizen.Effects.Map,
        Cizen.Effects.Monitor,
        Cizen.Effects.Race,
        Cizen.Effects.Receive,
        Cizen.Effects.Request,
        Cizen.Effects.Resume,
        Cizen.Effects.Start,
        Cizen.Effects.Subscribe
      ],
      "Effects Internal": [
        Cizen.Effects.HybridMap
      ],
      Effectful: [
        Cizen.Effectful
      ],
      Event: [
        Cizen.Event,
        Cizen.Filter,
        Cizen.EventID
      ],
      Requesting: [
        Cizen.Request,
        Cizen.Request.Response
      ],
      "Requesting Internal": [
        Cizen.RequestResponseMediator,
        Cizen.RequestResponseMediator.Worker
      ],
      Saga: [
        Cizen.CizenSagaRegistry,
        Cizen.CrashLogger,
        Cizen.EndSaga,
        Cizen.MonitorSaga,
        Cizen.MonitorSaga.Down,
        Cizen.ResumeSaga,
        Cizen.Saga,
        Cizen.Saga.Crashed,
        Cizen.Saga.Finish,
        Cizen.Saga.Finished,
        Cizen.Saga.Ended,
        Cizen.Saga.Started,
        Cizen.SagaID,
        Cizen.SagaMonitor,
        Cizen.SagaRegistry,
        Cizen.StartSaga
      ],
      "Saga Internal": [
        Cizen.SagaEnder,
        Cizen.SagaLauncher,
        Cizen.SagaLauncher.LaunchSaga,
        Cizen.SagaLauncher.UnlaunchSaga,
        Cizen.SagaResumer,
        Cizen.SagaStarter
      ],
      Test: [
        Cizen.Test
      ]
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
end
