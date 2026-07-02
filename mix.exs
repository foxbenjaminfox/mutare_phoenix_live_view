defmodule MutarePhoenixLiveView.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :mutare_phoenix_live_view,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      description: description(),
      package: package(),
      name: "Mutare Phoenix LiveView",
      source_url: "https://github.com/foxbenjaminfox/mutare_phoenix_live_view",
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # The companion base package — this one **builds on** it: it depends on it and
      # composes its preset (`Mutare.Phoenix.all/0`) with the LiveView families on top
      # (mirroring how `phoenix_live_view` depends on `phoenix`). `mutare` itself arrives
      # transitively through it. Path deps for local development until both are published;
      # a consuming project lists both as `:dev`/`:test` deps.
      {:mutare_phoenix, path: "../mutare_phoenix"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [check: ["format --check-formatted", "credo", "dialyzer"]]
  end

  # Mutators are pure AST transforms over Sourceror nodes, so the most useful
  # specs to verify are the `Mutare.Mutator` callbacks. The PLT lives in a
  # cacheable, gitignored directory; `:mix` and `:ex_unit` are pulled in because
  # `mix.exs` and `test/support` participate in the analysis.
  #
  # `:extra_return` is deliberately *off*: every AST-constructor helper returns one
  # concrete `Macro.t()` shape, so its natural `:: Macro.t()` spec is broader than the
  # single node it builds — exactly what `:extra_return` would flag. The remaining flags
  # add real strictness without fighting that grain.
  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_local_path: "priv/plts",
      plt_core_path: "priv/plts",
      flags: [:error_handling, :unmatched_returns]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md": [title: "Overview"],
        LICENSE: [title: "License"]
      ],
      source_ref: "v#{@version}",
      source_url: "https://github.com/foxbenjaminfox/mutare_phoenix_live_view"
    ]
  end

  defp description do
    "Custom Mutare mutators for Phoenix LiveView."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/foxbenjaminfox/mutare_phoenix_live_view"},
      files: ~w(lib mix.exs README.md LICENSE .formatter.exs)
    ]
  end
end
