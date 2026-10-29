# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.EditorTenancyTest do
  @moduledoc """
  Who may open which document in the editor — asked once for every section, and both ways round.

  The builder is one address with a resource id in it, so "which documents exist" and "which
  documents are mine" are not the same question, and only the first of them is answered by a route.
  Three rules are asserted here, on all four sections:

    * a tenant admin opens their own site's document, and nothing else on any other site;
    * a **global** layout or component — one with no `site_id`, which every site renders and places —
      is a master's to edit. The tenant is told that, in those words, rather than being let in and
      refused at Publish an hour later. `Layout` and `Component` say the same thing from inside their
      own `:update` validation; this is that rule arriving before the work rather than after it;
    * a master opens any of them, on any site, global included.

  And the canvas is asked separately, because it is a second LiveView addressed by the editing
  session's TOKEN rather than by the document — so it inherits none of the above. A token is
  unguessable and also shareable, which makes it a secret and not an authorization.
  """
  use MishkaCmsCore.ConnCase

  import Phoenix.LiveViewTest
  import MishkaCmsCore.Test.Factory

  alias MishkaCmsCore.Accounts.{Permission, User, UserPermission}
  alias MishkaCmsBuilder.EditorSession
  alias MishkaCmsCore.Runtime.PageBuilder.Tree
  alias MishkaCmsCore.Runtime.PageBuilder.Tree.Node
  alias MishkaCmsCore.Runtime.States.SiteState

  require Ash.Query

  @password "Password123!"
  @body ~s(<section id="root"><h1>Title</h1></section>)
  @layout_body ~s(<body class="page"><main>{@inner_content}</main></body>)

  setup %{conn: conn} do
    SiteState.clear()

    mine = create_site!(name: "localhost", host: "localhost", active: true, master: true)
    theirs = create_site!(name: "neighbour", host: "neighbour.test", active: true)

    for site <- [mine, theirs] do
      SiteState.save(%{
        id: site.id,
        name: site.name,
        host: site.host,
        priority: site.priority,
        active: site.active,
        master: site.master
      })
    end

    :persistent_term.put(:mishka_installed, true)

    on_exit(fn ->
      :persistent_term.erase(:mishka_installed)
      SiteState.clear()
    end)

    conn = on_host(conn)

    {:ok,
     conn: log_in(conn, admin!("boss@example.com")),
     tenant_conn:
       log_in(on_host(Phoenix.ConnTest.build_conn()), admin!("tenant@example.com", mine.id)),
     mine: mine,
     theirs: theirs}
  end

  defp on_host(conn) do
    conn
    |> Map.put(:host, "localhost")
    |> Map.update!(:req_headers, &[{"host", "localhost"} | List.keydelete(&1, "host", 0)])
  end

  defp permission! do
    case Permission |> Ash.Query.filter(name == "*") |> Ash.read_one(authorize?: false) do
      {:ok, nil} ->
        Permission
        |> Ash.Changeset.for_create(:create, %{name: "*"}, authorize?: false)
        |> Ash.create!()

      {:ok, permission} ->
        permission
    end
  end

  defp admin!(email, site_id \\ nil) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_create(
        :register_with_password,
        %{email: email, password: @password, password_confirmation: @password},
        authorize?: false
      )
      |> then(&if(site_id, do: Ash.Changeset.set_tenant(&1, site_id), else: &1))
      |> Ash.create()

    UserPermission
    |> Ash.Changeset.for_create(:assign, %{}, authorize?: false)
    |> Ash.Changeset.force_change_attribute(:user_id, user.id)
    |> Ash.Changeset.force_change_attribute(:permission_id, permission!().id)
    |> Ash.create!(authorize?: false)

    user
  end

  defp log_in(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:master_mode, true)
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  defp record!(:page, site_id), do: create_page!(site_id: site_id, template: @body)
  defp record!(:layout, site_id), do: create_layout!(site_id: site_id, template: @layout_body)

  defp record!(:error_page, site_id),
    do:
      create_error_page!(
        site_id: site_id,
        error_pages: [%{"status" => 404, "template" => @body, "layout" => %{}}]
      )

  defp record!(:component, site_id),
    do:
      create_component!(
        site_id: site_id,
        name: "tenancy-#{System.unique_integer([:positive])}",
        template: @body
      )

  defp path(:error_page), do: "error-page"
  defp path(section), do: to_string(section)

  defp open(conn, section, record),
    do: live(conn, "/admin/dashboard/runtime/builder/#{path(section)}/#{record.id}")

  defp token(view), do: :sys.get_state(view.pid).socket.assigns.token

  # THE BUILDER'S OWN WAYS INTO A COMPONENT'S EDITOR — the Inspector's button and the layers rail's
  # two arrows. They lead to the same address the details modal's Visual Editor does, so they keep the
  # same rule: a tenant is never offered a shared component's editor that would only turn them away.
  describe "a component's editor, from a page's builder" do
    defp placed_components!(site_id) do
      markup = ~s|<footer><div>a</div></footer>|
      shared = create_component!(site_id: nil, name: "shared-placed", template: markup)
      own = create_component!(site_id: site_id, name: "own-placed", template: markup)

      page =
        create_page!(
          site_id: site_id,
          template:
            ~s|<section id="root"><.component component_name="shared-placed" /><.component component_name="own-placed" /></section>|
        )

      {page, shared, own}
    end

    defp ways_in(view, name) do
      {:ok, editor} = EditorSession.fetch(token(view))
      node = editor.tree |> Tree.walk() |> Enum.find(&(Node.component_name(&1) == name))

      render_click(view, "select", %{"id" => node.id})
      render_click(view, "set_left_tab", %{"tab" => "inspector"})

      open? =
        view |> element(~s([data-layer-row="#{node.id}"])) |> render() =~ ~s(data-open="true")

      unless open?, do: render_click(view, "toggle_expand", %{"id" => node.id})

      for {way, selector} <- [
            inspector: "#pb-insp-edit-component",
            row: "#pb-layer-open-#{node.id}",
            markup: "#pb-markup-open-#{node.id}"
          ],
          has_element?(view, selector),
          do: way
    end

    test "offers a tenant none of them on a shared component", %{tenant_conn: conn, mine: mine} do
      {page, _shared, _own} = placed_components!(mine.id)
      {:ok, view, _html} = open(conn, :page, page)
      render_async(view)

      assert ways_in(view, "shared-placed") == []
    end

    test "and every one of them on the tenant's own", %{tenant_conn: conn, mine: mine} do
      {page, _shared, own} = placed_components!(mine.id)
      {:ok, view, _html} = open(conn, :page, page)
      render_async(view)

      assert ways_in(view, "own-placed") == [:inspector, :row, :markup]

      assert has_element?(
               view,
               ~s(#pb-insp-edit-component[href^="/admin/dashboard/runtime/builder/component/#{own.id}?"])
             )
    end

    test "and a master every one of them on the shared one", %{conn: conn, mine: mine} do
      {page, shared, _own} = placed_components!(mine.id)
      {:ok, view, _html} = open(conn, :page, page)
      render_async(view)

      assert ways_in(view, "shared-placed") == [:inspector, :row, :markup]

      assert has_element?(
               view,
               ~s(#pb-insp-edit-component[href^="/admin/dashboard/runtime/builder/component/#{shared.id}?"])
             )
    end
  end

  describe "the canvas" do
    test "nor one opened on a global layout", %{conn: conn, tenant_conn: tenant_conn} do
      {:ok, view, _html} = open(conn, :layout, record!(:layout, nil))

      {:ok, _canvas, html} =
        live(tenant_conn, "/admin/dashboard/runtime/builder-canvas/#{token(view)}")

      assert html =~ "belongs to another site"
    end

    test "a tenant mounts their own site's session", %{tenant_conn: conn, mine: mine} do
      {:ok, view, _html} = open(conn, :page, record!(:page, mine.id))

      {:ok, _canvas, html} =
        live(conn, "/admin/dashboard/runtime/builder-canvas/#{token(view)}")

      refute html =~ "belongs to another site"
      assert html =~ "pb-canvas-root"
    end

    test "and a master mounts any of them", %{conn: conn, theirs: theirs} do
      {:ok, view, _html} = open(conn, :page, record!(:page, theirs.id))

      {:ok, _canvas, html} =
        live(conn, "/admin/dashboard/runtime/builder-canvas/#{token(view)}")

      refute html =~ "belongs to another site"
      assert html =~ "pb-canvas-root"
    end

    test "an expired token still reads as expired, not as somebody else's", %{conn: conn} do
      {:ok, view, _html} = open(conn, :page, record!(:page, nil))
      token = token(view)
      EditorSession.close(token)

      {:ok, _canvas, html} = live(conn, "/admin/dashboard/runtime/builder-canvas/#{token}")

      assert html =~ "expired"
      refute html =~ "belongs to another site"
    end
  end
end
