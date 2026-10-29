# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.TestRouter do
  @moduledoc """
  The routes this package's tests drive, mirroring the scopes the CMS puts it in.

  `/admin/dashboard` is the CMS's `:browser` pipeline, and mounts the core's admin LiveViews and
  this package's through `extension_routes(:admin)` — the same macro the CMS uses, reading
  `config :mishka_cms_core, :extensions`, which here lists `MishkaCmsCoreWeb` and
  `MishkaCmsBuilderWeb`. The `on_mount` hooks are `MishkaCmsCore.LiveUserAuth`, standing in for the
  host's.

  It mounts `extension_routes(:admin_standalone)` in a SECOND `live_session`, as the CMS does, and
  that is where the editor lives. The boundary is the point of that list — LiveView will not
  live-navigate across one, so the visual editor is always entered on a fresh document with the head
  it asks for — and a harness that put both lists in one session would let a test pass where a
  browser would not.

  There is no `/api/json` scope: the editor has no API of its own, and the core's API is exercised by
  the core's suite.
  """

  use Phoenix.Router

  # `extension_routes/1` expands to `live/3` calls; `use MishkaCmsWeb, :router` gives the CMS these.
  import Phoenix.LiveView.Router
  use AshAuthentication.Phoenix.Router

  import MishkaCmsCore.ExtensionRouter
  import MishkaCmsCore.Runtime.Plugs.SiteLookupPlug, only: [confirm_tenant: 2]

  pipeline :browser do
    plug :route_accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MishkaCmsBuilder.TestLayouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MishkaCmsCore.Runtime.Plugs.SiteLookupPlug
    plug :load_from_session
    plug :confirm_tenant
    plug :set_actor, :user
  end

  # The /auth routes the core owns, mounted exactly as the CMS mounts them: the AshAuthentication
  # controller routes and the DELETE the sign-out page posts to. The sign-in pages are the CMS's
  # runtime pages, which this harness has no catch-all to serve.
  scope "/" do
    pipe_through [:browser]

    auth_routes MishkaCmsCoreWeb.AuthController, MishkaCmsCore.Accounts.User, path: "/api/auth"

    delete "/auth/sign-out", MishkaCmsCoreWeb.AuthController, :sign_out, as: :auth
  end

  # The public extension routes the CMS also mounts outside `/admin` — the per-site asset bundles,
  # robots.txt and the sitemap. A router that mounted only the admin routes could not exercise them.
  scope "/" do
    pipe_through [:browser]

    extension_routes(:public)
  end

  scope "/admin/dashboard" do
    pipe_through [:browser]

    ash_authentication_live_session :test_authenticated_routes,
      on_mount: [
        {MishkaCmsCore.LiveUserAuth, :live_user_required},
        {MishkaCmsCore.LiveUserAuth, {:require_permission, [{:under, "admin:dashboard"}]}}
      ] do
      extension_routes(:admin)
    end

    # The second session, mirroring the CMS again: the visual editor is routed apart from the rest of
    # the admin so that reaching it is a full page load and the root layout is re-rendered with the
    # head it needs. Omitting it here does not fail quietly — every builder route 404s — which is
    # how a harness should react to a router it no longer mirrors.
    ash_authentication_live_session :test_authenticated_standalone_routes,
      on_mount: [
        {MishkaCmsCore.LiveUserAuth, :live_user_required},
        {MishkaCmsCore.LiveUserAuth, {:require_permission, [{:under, "admin:dashboard"}]}}
      ] do
      extension_routes(:admin_standalone)
    end
  end
end
