defmodule Mutare.Phoenix.LiveView.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/foxbenjaminfox/mutare_phoenix_live_view"

  def project do
    [
      app: :mutare_phoenix_live_view,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      aliases: aliases(),
      dialyzer: dialyzer(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: []]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp description do
    "Mutare mutators for Phoenix LiveView"
  end

  # Hex package metadata. Only runtime and doc artifacts ship — never the test suite,
  # fixtures, or the examples app.
  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Benjamin Fox"],
      links: %{
        "GitHub" => @source_url,
        "Mutare" => "https://hexdocs.pm/mutare",
        "Changelog" => "https://hexdocs.pm/mutare_phoenix_live_view/changelog.html"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp deps do
    [
      # The host mutation-testing engine, declared directly: the families here implement
      # `Mutare.Mutator` and call its extension points (`Mutare.Calls`, `Mutare.AST`)
      # themselves, so the dependency is this package's own, not an accident of what
      # `mutare_phoenix` happens to pull in.
      {:mutare, "~> 0.1"},
      # The companion base package — this one **builds on** it: it depends on it and
      # composes its preset (`Mutare.Phoenix.all/0`) with the LiveView families on top
      # (mirroring how `phoenix_live_view` depends on `phoenix`). A consuming project
      # lists `mutare` and this package as `:dev`/`:test` deps.
      {:mutare_phoenix, "~> 0.1"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  # `mix check` is the single quality gate: formatting, lint, and type analysis.
  # Any non-zero step aborts the rest, so a green run means all three passed.
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

  # ExDoc configuration. `mix docs` renders to `doc/` (gitignored). README is the
  # landing page.
  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "LICENSE"],
      # `Stream`'s moduledoc names core's hidden overlap pass in prose (the reference
      # is worth keeping — it explains the at:-swap's supersession of core's integer
      # leaves); don't autolink to it, which also silences the "references hidden"
      # warning.
      skip_code_autolink_to: ["Mutare.Transform.Overlap"],
      groups_for_modules: [
        "Mutator front": [Mutare.Phoenix.LiveView],
        "Mutator families": [
          Mutare.Phoenix.LiveView.Navigation,
          Mutare.Phoenix.LiveView.Reply,
          Mutare.Phoenix.LiveView.Stream,
          Mutare.Phoenix.LiveView.Event,
          Mutare.Phoenix.LiveView.SendUpdate,
          Mutare.Phoenix.LiveView.Hook
        ]
      ]
    ]
  end
end
