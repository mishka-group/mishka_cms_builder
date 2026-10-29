# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

# This package's tests run on their own, and the difference matters.
#
# Standalone (`mix test` in this repository) there is no application around it, so everything a test
# touches has to be started here. A host — the CMS — already runs all of it, so when the helper is
# loaded from there it must do nothing at all: starting a second repo, endpoint or Oban on top of the
# host's would fight it.
#
# Everything that is not specific to the editor comes from the core's test harness
# (`MishkaCmsCore.Test.Boot`, shipped in the core's `lib`): the Oban tables, the caches and the
# runtime compiler's processes, the sign-in supervisor and the endpoint. What this package adds is the
# four processes of its own application (`MishkaCmsBuilder.Application`) and the plugins that
# register the editor's routes, pages and hooks, which the run waits for.
if Mix.Project.config()[:app] == :mishka_cms_builder do
  :ok =
    MishkaCmsCore.Test.Boot.start!(
      otp_app: :mishka_cms_builder,
      repo: MishkaCmsBuilder.Repo,
      endpoint: MishkaCmsBuilder.TestEndpoint,
      plugins: MishkaCmsCore.Application.plugins() ++ MishkaCmsBuilder.Application.plugins(),
      # A TEST PLUGIN THAT OUTLIVED ITS RUN. MishkaInstaller keeps registrations in Mnesia, which is
      # on disk and survives the run that made them, so a suite killed part-way leaves its plugin
      # registered forever and every later run boots with it live. Only the test plugins of this
      # package and of the core are swept — a real plugin belongs to whoever installed it.
      sweep: ["Elixir.MishkaCmsCore.Test.Plugins.", "Elixir.MishkaCmsBuilder.Test.Plugins."],
      # esbuild resolves the generated entry file's `import … from "phoenix"` through here: the
      # NODE_PATH `config/test.exs` gives it, in the checkout's `priv`. `Application.app_dir/2`
      # would name the compiled app's `priv`, a link that exists only once `mix ash.codegen` has made
      # the folder, and the two would then differ.
      # credo:disable-for-next-line ExSlop.Check.Warning.PathExpandPriv
      js_assets: Path.expand("../priv/static/temp/js_assets/node_modules", __DIR__)
    )

  # `render_async/1` WAITS THIS LONG, and 100ms is not a number anybody here chose. LiveView's
  # default is `Application.fetch_env!(:ex_unit, :assert_receive_timeout)`, and every `render_async`
  # in these suites is waiting on a real database load — the editor's `start_async` record fetch,
  # most of them. On a machine running another suite beside this one that load takes longer than
  # 100ms, and the test fails with "expected async processes to finish within 100ms" from a line that
  # was asserting something else entirely.
  #
  # Raising it here rather than at 156 call sites: it is the knob LiveView itself reads, it covers
  # every future `render_async` without anyone remembering, and it costs nothing on a passing run —
  # a longer timeout only delays FAILURES, never successes.
  #
  # The bound is the editor's own for its slowest mount task: opening it on a page that places a
  # runtime component awaits `warm_components`, a module compile the editor allows 30 seconds. One
  # second failed that wait while a second suite shared the machine.
  ExUnit.configure(assert_receive_timeout: :timer.seconds(30))

  # The `:performance` tests time the ETS states against a wall-clock limit, which a shared CI
  # machine misses now and then. They run on demand: `mix test --include performance`.
  ExUnit.configure(exclude: [:performance | ExUnit.configuration()[:exclude] || []])

  ExUnit.start()
  Ecto.Adapters.SQL.Sandbox.mode(MishkaCmsBuilder.Repo, :manual)
end
