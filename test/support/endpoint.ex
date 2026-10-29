# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.TestEndpoint do
  @moduledoc """
  The endpoint this package's suite runs against, doing two jobs at once:

    * it carries the test's HTTP and LiveView requests to `MishkaCmsBuilder.TestRouter`, and
    * it is what every resource broadcasts through on write, because `config/config.exs` names it as
      `config :mishka_cms_core, endpoint: …` — the setting each `pub_sub do module … end` reads.

  Everything the CMS's real endpoint carries and this one does not — static assets, the public site
  — is machinery the editor's tests never touch.

  Test-only: Mix does not compile a path dependency's `test/support`, so the CMS never sees this
  module, and `mix.exs` keeps `test` out of the hex `files:` list.
  """

  use Phoenix.Endpoint, otp_app: :mishka_cms_builder

  # The admin LiveViews mount over a session, so the browser pipeline needs one to fetch.
  @session_options [
    store: :cookie,
    key: "_mishka_cms_builder_test_key",
    signing_salt: "cms-builder-test",
    same_site: "Lax"
  ]

  # `:peer_data` and `:x_headers` as the CMS's: the `/auth` forms are rate limited by the address they
  # name.
  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:peer_data, :x_headers, session: @session_options]]

  # As the CMS's: `conn.remote_ip` is the client the proxies forwarded.
  plug RemoteIp, MishkaCmsCore.Accounts.AuthRateLimit.remote_ip_options()

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, {:json, length: 10_000_000}],
    pass: ["*/*"],
    json_decoder: Jason

  plug Plug.MethodOverride
  plug Plug.Session, @session_options
  plug Plug.Head
  plug MishkaCmsBuilder.TestRouter
end
