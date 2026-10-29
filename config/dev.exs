# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

import Config

config :mishka_cms_builder, MishkaCmsBuilder.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mishka_cms_builder_dev",
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :ash, policies: [show_policy_breakdowns?: true]

# The visual editor's Record history and Assistant rails show the prototype's sample transcript while
# they are empty, so the panels can be judged before a page has any real history or conversation.
# Scaffolding — see `MishkaCmsBuilder.Demo`; drop this line to see the real (empty) rails, and delete
# the module once real data exists.
config :mishka_cms_builder, demo_data: true
