# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

# Warnings `mix dialyzer` reports that are not defects. Each one is named by file, kind and line,
# so a new warning of the same kind in the same file is still reported.
[
  # MapSet, :sets and Phoenix.LiveView.JS are opaque types: dialyzer reports a call that reads one
  # through its struct, which is what the standard library and LiveView do themselves.
  {"lib/mishka_cms_builder/editor_session.ex", :call_with_opaque, 2258},
  {"lib/mishka_cms_builder/editor_session.ex", :call_with_opaque, 2261},
  {"lib/mishka_cms_builder/history.ex", :call_without_opaque, 432},
  {"lib/mishka_cms_builder/marketplace/kits.ex", :call_without_opaque, 62},
  {"lib/mishka_cms_builder_web/live/panels.ex", :call_without_opaque, 4373},
  {"lib/mishka_cms_builder_web/live/panels.ex", :call_without_opaque, 4418},

  # `Strict.violation!/2` and `Strict.check!/3` are the core's macros that compile to an
  # unconditional `raise` outside :prod (`builder_strict` in config/config.exs) and to nothing in
  # :prod, and `mix ci` runs dialyzer in :test. Every function that reaches one is "without a local
  # return", and what depends on it is "never called" or "never matches". The shipped (:prod) shape
  # has none of these.
  {"lib/mishka_cms_builder/blocks.ex", :invalid_contract, 473},
  {"lib/mishka_cms_builder/blocks.ex", :no_return, 474},
  {"lib/mishka_cms_builder/editor_session.ex", :no_return, 1548},
  {"lib/mishka_cms_builder/editor_session.ex", :no_return, 1591},
  {"lib/mishka_cms_builder/editor_session.ex", :no_return, 1619},
  {"lib/mishka_cms_builder/editor_session.ex", :pattern_match, 1908},
  {"lib/mishka_cms_builder/editor_session.ex", :pattern_match, 1916},
  {"lib/mishka_cms_builder/editor_session.ex", :pattern_match, 2868},
  {"lib/mishka_cms_builder/editor_session.ex", :unused_fun, 1939},
  {"lib/mishka_cms_builder/editor_session.ex", :unused_fun, 1941},
  {"lib/mishka_cms_builder/editor_session.ex", :unused_fun, 1943},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match, 1266},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match, 6315},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match, 7803},

  # A last clause that matches anything, after clauses the current callers already cover. Kept on
  # purpose: it is the answer to a shape a plugin, a stored row or a later caller may send.
  {"lib/mishka_cms_builder/editor_session/journal.ex", :pattern_match_cov, 415},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6225},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6547},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6719},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6795},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6827},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6858},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6870},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6882},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6894},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 7636},

  # `:elixir_tokenizer.tokenize/3` and the project's HEEx tokenizer are called through a clause for
  # each shape either has returned across Elixir releases; dialyzer sees the one of this release.
  {"lib/mishka_cms_builder/highlight.ex", :guard_fail, 93},
  {"lib/mishka_cms_builder/highlight.ex", :pattern_match, 76}
]
