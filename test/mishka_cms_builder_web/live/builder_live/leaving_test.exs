# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.LeavingTest do
  @moduledoc """
  The ways out of the editor, and how each one goes.

  The editor is routed in a live_session of its own (`MishkaCmsBuilderWeb.Routes`), and LiveView
  refuses a live navigation across that boundary: the server logs "navigate event … redirecting
  across live_sessions", the browser logs "unauthorized live_redirect" and only then loads the page.
  A link out of the editor is therefore a plain one, a way out the server takes is a redirect, and
  only a way to another of the editor's own pages is live. With work to lose in publish mode, the
  leave guard (`assets/test/pb_leave_guard.test.js`) hands either kind of click to `leaving`.
  """
  use MishkaCmsBuilder.LiveCase

  alias MishkaCmsBuilderWeb.Paths

  @list "/admin/dashboard/runtime/pages"

  # The `data-phx-link` of the anchors matching `selector`: `[]` for plain links, `["redirect"]` for
  # a live one.
  defp link_kinds(view, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> tap(&refute(Enum.empty?(&1), "no link matches #{selector}"))
    |> LazyHTML.attribute("data-phx-link")
  end

  defp unpublished_change(view) do
    render_click(view, "set_stage", %{"stage" => "published"})
    render_click(view, "op", %{"kind" => "delete", "node_id" => node_with_tag(view, "h1").id})
    view
  end

  describe "the links out" do
    test "Back to the list is a plain link", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)

      assert link_kinds(view, ~s(#pb-back[href="#{@list}"])) == []
    end

    test "Back to the editor it was opened from stays a live link", %{
      conn: conn,
      page: page,
      site: site
    } do
      component = create_component!(site_id: site.id, name: "leave-card")
      from = Paths.builder_path("page", page.id)
      query = URI.encode_query(%{"return_to" => from})

      {:ok, view, _html} =
        live(conn, "/admin/dashboard/runtime/builder/component/#{component.id}?#{query}")

      _settled = render_async(view)

      assert link_kinds(view, ~s(#pb-back[href="#{from}"])) == ["redirect"]
    end

    test "the command palette's pages of the admin are plain links", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)
      render_click(view, "toggle_command")

      assert view |> link_kinds(~s([id^="pb-goto-"])) |> Enum.uniq() == []
    end

    test "the Studio's way to the stylesheets is a plain link", %{conn: conn, page: page} do
      view = open_studio(conn, page)

      assert link_kinds(view, ~s(a[href="/admin/dashboard/runtime/stylesheets"])) == []
    end

    test "a new document's way back to the list is a plain link", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/dashboard/runtime/builder/page")

      assert link_kinds(view, ~s(a[href="#{@list}"])) == []
    end
  end

  describe "the ways out the server takes" do
    test "leaving with nothing at stake is a page load to the rest of the admin", %{
      conn: conn,
      page: page
    } do
      {:ok, view, _html} = open_builder(conn, page)

      assert {:error, {:redirect, %{to: @list}}} = render_click(view, "leaving", %{"to" => @list})
    end

    test "and a live navigation to another of the editor's pages", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)
      to = Paths.builder_path("component", Ecto.UUID.generate())

      assert {:error, {:live_redirect, %{to: ^to}}} = render_click(view, "leaving", %{"to" => to})
    end

    for {button, what} <- [
          {"#pb-leave-go", "Leave anyway"},
          {"#pb-leave-save", "Keep as a draft"},
          {"#pb-leave-publish", "Publish it now"}
        ] do
      test "#{what} leaves for the list with a page load", %{conn: conn, page: page} do
        {:ok, view, _html} = open_builder(conn, page)
        unpublished_change(view)

        render_click(view, "leaving", %{"to" => @list})

        assert {:error, {:redirect, %{to: @list}}} =
                 view |> element(unquote(button)) |> render_click()
      end
    end

    test "a destination with a backslash is not a path of this app", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)
      unpublished_change(view)

      render_click(view, "leaving", %{"to" => "/\\elsewhere.test"})

      refute has_element?(view, "#pb-leave-modal")
    end

    test "backing out of a new document is a page load to the list", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/dashboard/runtime/builder/page")
      watch = Process.monitor(view.pid)

      send(view.pid, {:form_cancelled, MishkaCmsCore.Runtime.Page})

      assert_receive {:DOWN, ^watch, :process, _pid, {:shutdown, {:redirect, %{to: @list}}}}
    end
  end
end
