# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

# Warnings `mix dialyzer` reports that are not defects. Each one is named by file, kind and line,
# so a new warning of the same kind in the same file is still reported.
[
  # MapSet, :sets and Phoenix.LiveView.JS are opaque types: dialyzer reports a call that reads one
  # through its struct, which is what the standard library and LiveView do themselves.
  {"lib/mishka_cms_builder/editor_session.ex", :call_with_opaque, 2232},
  {"lib/mishka_cms_builder/editor_session.ex", :call_with_opaque, 2235},
  {"lib/mishka_cms_builder/history.ex", :call_without_opaque, 427},
  {"lib/mishka_cms_builder/marketplace/kits.ex", :call_without_opaque, 62},
  {"lib/mishka_cms_builder_web/live/panels.ex", :call_without_opaque, 4328},
  {"lib/mishka_cms_builder_web/live/panels.ex", :call_without_opaque, 4373},

  # `Strict.violation!/2` and `Strict.check!/3` are the core's macros that compile to an
  # unconditional `raise` outside :prod (`builder_strict` in config/config.exs) and to nothing in
  # :prod, and `mix ci` runs dialyzer in :test. Every function that reaches one is "without a local
  # return", and what depends on it is "never called" or "never matches". The shipped (:prod) shape
  # has none of these.
  {"lib/mishka_cms_builder/blocks.ex", :invalid_contract, 473},
  {"lib/mishka_cms_builder/blocks.ex", :no_return, 474},
  {"lib/mishka_cms_builder/editor_session.ex", :no_return, 1538},
  {"lib/mishka_cms_builder/editor_session.ex", :no_return, 1581},
  {"lib/mishka_cms_builder/editor_session.ex", :no_return, 1609},
  {"lib/mishka_cms_builder/editor_session.ex", :pattern_match, 1882},
  {"lib/mishka_cms_builder/editor_session.ex", :pattern_match, 1890},
  {"lib/mishka_cms_builder/editor_session.ex", :pattern_match, 2842},
  {"lib/mishka_cms_builder/editor_session.ex", :unused_fun, 1913},
  {"lib/mishka_cms_builder/editor_session.ex", :unused_fun, 1915},
  {"lib/mishka_cms_builder/editor_session.ex", :unused_fun, 1917},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match, 1127},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match, 6026},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match, 7471},

  # A last clause that matches anything, after clauses the current callers already cover. Kept on
  # purpose: it is the answer to a shape a plugin, a stored row or a later caller may send.
  {"lib/mishka_cms_builder/editor_session/journal.ex", :pattern_match_cov, 415},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 5936},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6258},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6427},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6503},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6535},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6566},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6578},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6590},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 6602},
  {"lib/mishka_cms_builder_web/live/builder_live.ex", :pattern_match_cov, 7304},

  # `:elixir_tokenizer.tokenize/3` and the project's HEEx tokenizer are called through a clause for
  # each shape either has returned across Elixir releases; dialyzer sees the one of this release.
  {"lib/mishka_cms_builder/highlight.ex", :guard_fail, 93},
  {"lib/mishka_cms_builder/highlight.ex", :pattern_match, 76}
]
