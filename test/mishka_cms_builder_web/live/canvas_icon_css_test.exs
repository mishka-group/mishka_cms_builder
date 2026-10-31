# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.CanvasIconCssTest do
  @moduledoc """
  A glyph the page can draw has a rule in the frame, wherever the component keeps its name.

  The site's own stylesheet is generated from what its pages RENDER, so an icon a component only
  DEFAULTS to has no rule and draws as an empty box on the canvas. The canvas makes up the
  difference by emitting rules for every icon the document could draw — and it looked for those
  names in `{:string, …}` attributes only.

  `chelekom-pagination` declares its five arrows and its separator as `map`, each defaulting to
  `%{type: :icon, value: "hero-chevron-left"}`. Not one of them was found, so a dropped pagination
  drew empty boxes where its arrows should be — which is what it was reported as, alongside the
  page count that made it draw no pages at all.

  The walk is over the TERM now, not over a shape, so a name nested in a map, in a list, or written
  by hand as an expression is found the same way.
  """
  use MishkaCmsCore.ConnCase

  import MishkaCmsBuilder.LiveCase, only: [token: 1]

  import ExUnit.CaptureLog
  import Phoenix.LiveViewTest
  import MishkaCmsCore.Test.Factory

  alias MishkaCmsCore.Accounts.{Permission, User, UserPermission}
  alias MishkaCmsCore.Runtime.States.SiteState

  require Ash.Query

  @password "Password123!"

  # What the bundle carries for `previous_label` — an atom-keyed map, serialized.
  @map_default %{"__atom_map__" => [[":type", ":icon"], [":value", "hero-chevron-left"]]}

  @drawn ~S|<nav class="pager"><span class={@label[:value]}></span>{render_slot(@inner_block)}</nav>|

  setup %{conn: conn} do
    SiteState.clear()
    site = create_site!(name: "localhost", host: "localhost", active: true, master: true)
    cache_site(site)
    :persistent_term.put(:mishka_installed, true)

    on_exit(fn ->
      :persistent_term.erase(:mishka_installed)
      SiteState.clear()
    end)

    create_component!(
      site_id: site.id,
      name: "acme-pager",
      template: @drawn,
      attrs: [%{"name" => "label", "type" => "map", "opts" => %{"default" => @map_default}}]
    )

    define_component!("acme-pager", site, ~s(<nav class="pager"></nav>))

    page =
      create_page!(
        site_id: site.id,
        template:
          ~s(<div id="wrap"><.component component_name="acme-pager" site="#{site.name}" id="p1" /></div>)
      )

    conn =
      conn
      |> Map.put(:host, "localhost")
      |> Map.update!(:req_headers, &[{"host", "localhost"} | List.keydelete(&1, "host", 0)])

    {:ok, conn: log_in(conn, admin("canvas-icons@example.com")), site: site, page: page}
  end

  defp cache_site(site) do
    SiteState.save(%{
      id: site.id,
      name: site.name,
      host: site.host,
      priority: site.priority,
      active: site.active,
      master: site.master
    })
  end

  defp permission!(name) do
    case Permission |> Ash.Query.filter(name == ^name) |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        Permission
        |> Ash.Changeset.for_create(:create, %{name: name}, authorize?: false)
        |> Ash.create!()

      {:ok, permission} ->
        permission
    end
  end

  defp admin(email) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_create(
        :register_with_password,
        %{email: email, password: @password, password_confirmation: @password},
        authorize?: false
      )
      |> Ash.create()

    UserPermission
    |> Ash.Changeset.for_create(:assign, %{}, authorize?: false)
    |> Ash.Changeset.force_change_attribute(:user_id, user.id)
    |> Ash.Changeset.force_change_attribute(:permission_id, permission!("*").id)
    |> Ash.create!(authorize?: false)

    user
  end

  defp log_in(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:master_mode, true)
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  defp canvas_html(conn, page) do
    {:ok, view, _html} = live(conn, "/admin/dashboard/runtime/builder/page/#{page.id}")
    render_async(view)
    token = token(view)
    {:ok, _canvas, html} = live(conn, "/admin/dashboard/runtime/builder-canvas/#{token}")
    html
  end

  describe "the rules the frame carries" do
    test "cover an icon a component defaults to inside a map", %{conn: conn, page: page} do
      html = canvas_html(conn, page)

      assert html =~ "hero-chevron-left",
             "the glyph has no rule in the frame, so it draws as an empty box"
    end

    test "and one written on the page as an ordinary name", %{conn: conn, site: site} do
      page =
        create_page!(
          site_id: site.id,
          template: ~s(<div id="w2"><span class="hero-star"></span></div>)
        )

      assert canvas_html(conn, page) =~ "hero-star"
    end

    test "and nothing for a word that is not an icon", %{conn: conn, site: site} do
      page =
        create_page!(
          site_id: site.id,
          template: ~s(<div id="w3"><span class="not-an-icon-at-all"></span></div>)
        )

      refute canvas_html(conn, page) =~ "not-an-icon-at-all{"
    end
  end

  # AN ICON NAME THE CANVAS CANNOT COMPUTE STANDS IN AS AN ICON. `name={assigns[:icon]}` has no value
  # without the page's assigns, and the stand-in for any other string is shaped like a DOM id,
  # `pb-<id>-name`. An icon's body reads that name as `"hero-" <> _` and raised: a kit icon was
  # logged "body did not apply" on every render while the palette had not arrived, and core's
  # `<.icon>` drew the "could not render" box.
  describe "an icon name the canvas cannot compute" do
    test "stands in as a real icon on core's `<.icon>`", %{conn: conn, site: site} do
      page =
        create_page!(
          site_id: site.id,
          template: ~s(<div id="w4"><.icon name={assigns[:icon]} /></div>)
        )

      html = canvas_html(conn, page)

      assert html =~ "hero-sparkles size-4"
      refute html =~ ~r/pb-n[a-z0-9]{8}-name/
      refute html =~ "could not render"
    end

    test "and on a kit component whose attribute is an icon", %{conn: conn, site: site} do
      create_component!(
        site_id: site.id,
        name: "acme-glyph",
        template: ~S|<span class={["glyph", @name]}></span>|,
        body: ~S|%{name: "hero-" <> _} = assigns = assigns|,
        attrs: [%{"name" => "name", "type" => "string", "opts" => %{"editor" => "icon"}}]
      )

      page =
        create_page!(
          site_id: site.id,
          template:
            ~s(<div id="w5"><.component component_name="acme-glyph" site="#{site.name}" name={assigns[:icon]} /></div>)
        )

      log = capture_log(fn -> send(self(), {:html, canvas_html(conn, page)}) end)
      assert_received {:html, html}

      assert html =~ "glyph hero-sparkles"
      refute html =~ ~r/pb-n[a-z0-9]{8}-name/
      refute log =~ "did not apply"
    end
  end
end
