# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.MixProject do
  use Mix.Project

  @version "0.0.1"
  @source_url "https://github.com/mishka-group/mishka_cms_builder"

  def project do
    [
      app: :mishka_cms_builder,
      name: "Mishka CMS Builder",
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :dev,
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      description: description(),
      package: package(),
      homepage_url: "https://mishka.tools/cms",
      source_url: @source_url,
      docs: [
        main: "readme",
        source_ref: "v#{@version}",
        extras: ["README.md", LICENSE: [title: "License"]],
        source_url: @source_url
      ],
      # `test/support` is compiled in the test env, where `mix ci` runs dialyzer, and it calls
      # `ExUnit`, which is not in the default PLT. `.dialyzer_ignore.exs` lists what dialyzer
      # reports that is not a defect, each with the reason.
      dialyzer: [plt_add_apps: [:ex_unit], ignore_warnings: ".dialyzer_ignore.exs"]
    ]
  end

  def cli do
    [preferred_envs: [ci: :test]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MishkaCmsBuilder.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # `Spark.Formatter` needs it.
      {:sourceror, "~> 1.13", only: [:dev, :test]},
      # `Phoenix.LiveViewTest` parses rendered markup with this. Test-only: it is never a burden on
      # anything that depends on this library.
      {:lazy_html, "~> 0.1", only: :test},
      # The editor's Heroicons catalogue (`MishkaCmsCore.Runtime.Authoring.Icons.Heroicons`) reads
      # these SVGs at compile time, out of the deps of the project being built. A host brings its own
      # copy, so this one serves only this library's own suite, and it is never a requirement of the
      # Hex package.
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1,
       only: [:dev, :test]},
      {:ash, "~> 3.37"},
      {:ash_postgres, "~> 2.15"},
      {:ash_phoenix, "~> 2.3"},
      # 1.2.10 brought `navigation_type/2`, which the editor asks before it leaves.
      {:phoenix_live_view, "~> 1.2 and >= 1.2.10"},
      mishka_dep(:mishka_installer, "~> 0.1.14"),
      {:guarded_struct, "~> 0.1.4"},
      # 0.0.3 is the first core release with the seams this package plugs into
      # (`runtime:document:editor_url`, `runtime:provision:snippets`, `activity:sources`,
      # `MishkaCmsCore.Supervision`, `MishkaCmsCore.Test.Boot`); until it is on Hex a sibling
      # checkout of core's `feat/separation` branch stands in for it.
      mishka_dep(:mishka_cms_core, "~> 0.0.3"),
      mishka_dep(:mishka_gervaz, "~> 0.0.2"),
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.16", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:jump_credo_checks, "~> 0.6", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_dna, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      # `mix hex.publish` builds the docs with it.
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

  # A Mishka package is its sibling checkout `../<name>` when there is one, and its Hex release
  # otherwise. Only a git checkout counts, so the copy Mix fetched into a host's `deps/` never does,
  # and a `hex.*` task (`mix hex.build`, `mix hex.publish`) always takes Hex, as a package must.
  defp mishka_dep(name, requirement) do
    sibling? =
      File.dir?(Path.expand("../#{name}/.git", __DIR__)) and
        not Enum.any?(System.argv(), &String.starts_with?(&1, "hex."))

    case sibling? do
      true -> {name, path: "../#{name}"}
      false -> {name, requirement}
    end
  end

  defp description() do
    "The visual page builder for Mishka CMS: a drag-and-drop editor for pages, layouts and components, built on Phoenix LiveView."
  end

  # `lib` and the ESM hooks a host imports: `assets/js`, reached through `package.json`'s `main`
  # (the host's `import BuilderHooks from "mishka_cms_builder"`). The tests of those hooks live in
  # `assets/test` and do not ship. NOTHING UNDER `priv` SHIPS: it is the migrations and snapshots
  # `mix ash.codegen` generates for the standalone test database, including tables this package does
  # not own, and a runtime cache (`priv/static/temp`), so publishing it would ship someone else's
  # schema. `config` and `test` are absent for the same reason — they exist only to run the suite on
  # its own.
  defp package() do
    [
      licenses: ["Apache-2.0"],
      maintainers: ["Shahryar Tavakkoli"],
      files: ~w(lib assets/js package.json .formatter.exs mix.exs LICENSE README*),
      links: %{
        "Mishka CMS" => "https://mishka.tools/cms",
        "Official document" => "https://mishka.tools/cms/docs",
        "GitHub" => @source_url,
        "Sponsor" => "https://github.com/sponsors/mishka-group",
        "Contributors" => "#{@source_url}/graphs/contributors"
      }
    ]
  end

  defp aliases() do
    [
      test: ["ash.setup --quiet", "test"],
      setup: "ash.setup",
      ci: [
        # First: after `compile` Mix has pruned its code path and the Hex archive's task is gone.
        "hex.audit",
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "sobelow --config",
        "deps.audit",
        "dialyzer",
        # The 4 left repeat by design: the review note's and the snippet's Ash resource header and
        # policies, the typed-value helpers of their two Gervaz forms, and the `drag_start` answer
        # the editor and its canvas each give; a new clone fails the build.
        "ex_dna --max-clones 4",
        "test"
      ]
    ]
  end

  defp elixirc_paths(:test),
    do: elixirc_paths(:dev) ++ ["test/support"]

  defp elixirc_paths(_),
    do: ["lib"]
end
