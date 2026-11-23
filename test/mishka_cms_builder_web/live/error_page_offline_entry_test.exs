# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.ErrorPageOfflineEntryTest do
  @moduledoc """
  The offline page and the default page in the Error Pages admin, as the visual editor adds them: the
  editor opens a status the row lacks empty, and saving what is built there writes the entry beside
  the others. The form that offers the statuses and the preview's picker are asserted in the core.

  Its own file: nothing else drives the Error Pages index as a LiveView.
  """
  use MishkaCmsCore.ConnCase

  import MishkaCmsBuilder.LiveCase, only: [live_assigns: 1]
  import Phoenix.LiveViewTest
  import MishkaCmsCore.Test.Factory

  alias MishkaCmsBuilderWeb.Live.BuilderLive
  alias MishkaCmsCore.Accounts.{Permission, User, UserPermission}
  alias MishkaCmsCore.Runtime.Authoring.PageStarter
  alias MishkaCmsCore.Runtime.Authoring.Section
  alias MishkaCmsCore.Runtime.Authoring.Tree
  alias MishkaCmsCore.Runtime.{ErrorAddress, ErrorPage}
  alias MishkaCmsCore.Runtime.States.SiteState

  require Ash.Query

  @password "Password123!"

  # A core release older than the default entry does not offer it.
  @no_default_entry :default not in Section.offered_statuses() &&
                      "this core has no default entry"

  setup %{conn: conn} do
    SiteState.clear()
    site = create_site!(name: "localhost", host: "localhost", active: true, master: true)

    SiteState.save(%{
      id: site.id,
      name: site.name,
      host: site.host,
      priority: site.priority,
      active: site.active,
      master: site.master
    })

    :persistent_term.put(:mishka_installed, true)
    on_exit(fn -> :persistent_term.erase(:mishka_installed) end)

    conn =
      conn
      |> Map.put(:host, "localhost")
      |> Map.update!(:req_headers, &[{"host", "localhost"} | List.keydelete(&1, "host", 0)])
      |> log_in(create_admin("tenant@example.com", site.id))

    row =
      ErrorPage
      |> Ash.Changeset.for_create(
        :create,
        %{
          name: "localhost errors",
          path: ErrorAddress.path(site.name),
          error_pages: [
            %{status: 404, template: "<p>Not here</p>"},
            %{status: 500, template: "<p>Broke</p>"}
          ]
        },
        tenant: site.id,
        authorize?: false
      )
      |> Ash.create!()

    {:ok, conn: conn, site: site, row: row}
  end

  defp star_permission do
    Permission
    |> Ash.Query.filter(name == "*")
    |> Ash.read_one!(authorize?: false)
    |> case do
      nil -> create_permission!(name: "*")
      permission -> permission
    end
  end

  defp create_admin(email, site_id) do
    {:ok, user} =
      User
      |> Ash.Changeset.for_create(
        :register_with_password,
        %{email: email, password: @password, password_confirmation: @password},
        authorize?: false
      )
      |> Ash.Changeset.set_tenant(site_id)
      |> Ash.create()

    UserPermission
    |> Ash.Changeset.for_create(:assign, %{}, authorize?: false)
    |> Ash.Changeset.force_change_attribute(:user_id, user.id)
    |> Ash.Changeset.force_change_attribute(:permission_id, star_permission().id)
    |> Ash.create!(authorize?: false)

    user
  end

  defp log_in(conn, user) do
    conn
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:master_mode, true)
    |> AshAuthentication.Plug.Helpers.store_in_session(user)
  end

  defp stored(row), do: Ash.get!(ErrorPage, row.id, tenant: row.site_id, authorize?: false)

  # The builder opens a status the row lacks empty, and saving what is built there writes the entry
  # beside the others.
  test "the builder adds the offline page beside the row's entries", %{conn: conn, row: row} do
    {:ok, builder, _html} = live(conn, "/admin/dashboard/runtime/builder/error-page/#{row.id}")
    refute has_element?(builder, "#pb-status-offline")

    assert {:error, {:live_redirect, %{to: to}}} =
             builder |> element("#pb-status-add-offline") |> render_click()

    {:ok, builder, _html} = live(conn, to)
    assert has_element?(builder, "#pb-status-offline")

    render_click(builder, "drop", %{
      "template" => "<h1>Back soon</h1>",
      "parent_id" => "root",
      "index" => "0"
    })

    render_click(builder, "publish", %{})

    assert Map.new(stored(row).error_pages, &{&1.status, &1.template}) |> Map.take([404, 500]) ==
             %{404 => "<p>Not here</p>", 500 => "<p>Broke</p>"}

    assert Enum.find(stored(row).error_pages, &(&1.status == :offline)).template =~ "Back soon"
  end

  # An entry nobody has built on answers its errors with a blank page.
  test "an entry that is still empty is not published, and is once something is on it", %{
    conn: conn,
    row: row
  } do
    {:ok, builder, _html} =
      live(conn, "/admin/dashboard/runtime/builder/error-page/#{row.id}?status=offline")

    render_async(builder)
    refused = render_click(builder, "publish", %{})

    assert refused =~ "Not published"
    assert refused =~ "this error page is empty"
    assert Enum.map(stored(row).error_pages, & &1.status) == [404, 500]

    render_click(builder, "drop", %{
      "template" => "<h1>Back soon</h1>",
      "parent_id" => "root",
      "index" => "0"
    })

    render_click(builder, "publish", %{})
    assert Enum.map(stored(row).error_pages, & &1.status) == [404, 500, :offline]
  end

  test "nor is one whose content was taken away", %{conn: conn, row: row} do
    {:ok, builder, _html} =
      live(conn, "/admin/dashboard/runtime/builder/error-page/#{row.id}?status=404")

    render_async(builder)
    [root] = live_assigns(builder).editor.tree.roots
    render_click(builder, "op", %{"kind" => "delete", "node_id" => root})

    assert render_click(builder, "publish", %{}) =~ "this error page is empty"
    assert %{template: "<p>Not here</p>"} = hd(stored(row).error_pages)
  end

  defp problems(markup),
    do: BuilderLive.problems(%{section: "error-page", tree: Tree.parse!(markup), components: []})

  test "nor is one that shows a visitor nothing", %{conn: conn, row: row} do
    for markup <- [
          "",
          "<div></div>",
          "<!-- to do -->",
          "<%!-- to do --%>",
          PageStarter.blank(),
          "<section class=\"p-8\">\n  <div><p> </p><br /></div>\n  <!-- here -->\n</section>",
          "<div data-pb-hidden><h1>Back soon</h1></div>",
          "<style>p { color: red }</style><div></div>"
        ] do
      assert [%{kind: :empty}] = problems(markup), "published as it is: #{markup}"
    end

    for markup <- [
          "<h1>Not here</h1>",
          "<div><p>{@status}</p></div>",
          "<%= if @status == 404 do %>Gone<% end %>",
          "<div><img src=\"/gone.png\" alt=\"\" /></div>",
          "<video src=\"/gone.mp4\"></video>",
          "<form><input name=\"q\" /></form>",
          "<svg viewBox=\"0 0 1 1\"><path d=\"M0 0\" /></svg>",
          "<div><hr /></div>",
          "<my-widget></my-widget>",
          "<div id=\"drawn\" phx-hook=\"Drawn\"></div>",
          "<div class=\"h-screen bg-[url(/gone.png)]\"></div>",
          "<div style=\"background: url(/gone.png)\"></div>",
          "<.component component_name=\"site-footer\" site=\"Global\" />"
        ] do
      refute Enum.any?(problems(markup), &(&1.kind == :empty)), "refused as empty: #{markup}"
    end

    {:ok, builder, _html} =
      live(conn, "/admin/dashboard/runtime/builder/error-page/#{row.id}?status=offline")

    render_async(builder)

    render_click(builder, "drop", %{
      "template" => PageStarter.scratch(),
      "parent_id" => "root",
      "index" => "0"
    })

    assert render_click(builder, "publish", %{}) =~ "this error page is empty"
    assert Enum.map(stored(row).error_pages, & &1.status) == [404, 500]
  end

  # Opening another status leaves it out of the strip, so it says so while it is open.
  test "a status being added says it is not published yet, until it is", %{conn: conn, row: row} do
    path = "/admin/dashboard/runtime/builder/error-page/#{row.id}"

    {:ok, builder, _html} = live(conn, path <> "?status=404")
    refute has_element?(builder, "#pb-status-unpublished")

    {:ok, builder, _html} = live(conn, path <> "?status=offline")
    render_async(builder)
    assert has_element?(builder, "#pb-status-unpublished", "Not published yet")

    render_click(builder, "drop", %{
      "template" => "<h1>Back soon</h1>",
      "parent_id" => "root",
      "index" => "0"
    })

    render_click(builder, "publish", %{})
    refute has_element?(builder, "#pb-status-unpublished")
  end

  # What is typed in the Code Editor and not applied is the browser's, so it is the browser that asks
  # (`PbLeaveGuard`); every button that publishes carries what it asks, and so does the guard.
  test "every Publish button, and leaving, carries the question about code that is not applied",
       %{
         conn: conn,
         row: row
       } do
    {:ok, builder, _html} = live(conn, "/admin/dashboard/runtime/builder/error-page/#{row.id}")
    render_async(builder)

    assert has_element?(builder, "#pb-stage-publish-now[data-unapplied*='Apply']")

    refute has_element?(builder, "#pb-stage[data-unapplied]"),
           "the draft button publishes nothing"

    render_click(builder, "set_stage", %{"stage" => "published"})
    assert has_element?(builder, "#pb-stage[data-unapplied]")
    assert has_element?(builder, "#pb-leave-guard[data-unapplied*='leaving']")
  end

  @tag skip: @no_default_entry
  test "the builder adds the default page, whose tab, preview and invitation name it", %{
    conn: conn,
    row: row
  } do
    {:ok, builder, _html} = live(conn, "/admin/dashboard/runtime/builder/error-page/#{row.id}")
    refute has_element?(builder, "#pb-status-default")
    assert has_element?(builder, "#pb-status-add-offline + #pb-status-add-default", "Default")

    assert {:error, {:live_redirect, %{to: to}}} =
             builder |> element("#pb-status-add-default") |> render_click()

    {:ok, builder, _html} = live(conn, to)
    assert has_element?(builder, "#pb-status-default", "Default")

    render_click(builder, "drop", %{
      "template" => "<h1>Something went wrong</h1>",
      "parent_id" => "root",
      "index" => "0"
    })

    render_click(builder, "publish", %{})

    by_status = Map.new(stored(row).error_pages, &{&1.status, &1.template})
    assert %{404 => "<p>Not here</p>", 500 => "<p>Broke</p>"} = by_status
    assert by_status[:default] =~ "Something went wrong"

    render_click(builder, "save_as_draft", %{"label" => "Shareable"})
    assert has_element?(builder, "#pb-preview-tab[href*='?status=default']")

    assert BuilderLive.share_url(live_assigns(builder)) =~ "status=default"
  end
end
