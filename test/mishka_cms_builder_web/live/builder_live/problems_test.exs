# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.ProblemsTest do
  @moduledoc """
  The red dot beside the status: what Publish would refuse, counted, listed by element, and one
  click from the element it is about.

  The canvas drew "needs name" where Publish then succeeded, and Publish refused with a flash naming
  a field several rows inside a component that may not even be open. The dot, its window and the
  refusal now read one list, `BuilderLive.problems/1`, which is the publish gate itself.
  """
  use MishkaCmsBuilder.LiveCase

  alias MishkaCmsBuilderWeb.Live.BuilderLive

  defp needy_page(site) do
    needy(site.id)

    create_page!(
      site_id: site.id,
      template: ~s|<section id="hero"><.component component_name="needful" /></section>|
    )
  end

  defp dot(view), do: view |> element("#pb-problems-dot") |> render()

  describe "the red dot" do
    test "counts what Publish refuses", %{conn: conn, site: site} do
      {:ok, view, _html} = open_builder(conn, needy_page(site))

      assert dot(view) =~ ~r/>\s*2\s*</, "one blank required property and one missing slot"
      assert dot(view) =~ "2 problems stop a publish"
      assert length(BuilderLive.problems(editor(view))) == 2
    end

    test "is not there when nothing stops a publish", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)

      refute has_element?(view, "#pb-problems-dot")
      refute has_element?(view, "#pb-problems-modal")
    end

    test "goes once the last problem is fixed", %{conn: conn, site: site} do
      {:ok, view, _html} = open_builder(conn, needy_page(site))
      node = needful_node(view)

      render_click(view, "op", %{"kind" => "delete", "node_id" => node.id})

      refute has_element?(view, "#pb-problems-dot")
    end

    # SHOWN AND HIDDEN IN THE BROWSER, and marked a modal only while it is open, so Escape is its
    # own and the editor's keyboard hook stands back as it does for every other modal.
    test "opens its window with LiveView.JS, marking it a modal that owns Escape", %{
      conn: conn,
      site: site
    } do
      {:ok, view, _html} = open_builder(conn, needy_page(site))

      opens = view |> element("#pb-problems-dot") |> render() |> attribute("phx-click")
      assert opens =~ ~s("show") and opens =~ "#pb-problems-modal"
      assert opens =~ ~s("data-pb-modal")

      modal = view |> element("#pb-problems-modal") |> render()
      assert opening_tag(modal) =~ ~s(phx-key="escape")
      assert opening_tag(modal) =~ "phx-window-keydown"
      refute opening_tag(modal) =~ ~r/\sdata-pb-modal[\s=>]/, "shut, it must not hold Escape"
    end
  end

  describe "the window" do
    test "lists every problem under the element it is about", %{conn: conn, site: site} do
      {:ok, view, _html} = open_builder(conn, needy_page(site))
      node = needful_node(view)

      group = view |> element(~s([data-problem-group="#{node.id}"])) |> render()

      assert group =~ "section › needful"
      assert group =~ "needful.src is required and empty"
      assert group =~ "needful.:caption is required and empty"
    end

    test "takes a click to the element, with the Inspector on the property", %{
      conn: conn,
      site: site
    } do
      {:ok, view, _html} = open_builder(conn, needy_page(site))
      node = needful_node(view)

      view
      |> element(
        ~s(#pb-problems-modal button[data-problem-node="#{node.id}"][data-problem-field="src"])
      )
      |> render_click()

      assert editor(view).selection == node.id
      assert live_assigns(view).left_tab == :inspector
      assert live_assigns(view).focus_attr == "src"
      assert has_element?(view, ~s([data-role="pb-crumbs"] button), "needful")
    end

    test "names a problem of the whole document under the document", %{conn: conn, site: site} do
      layout =
        create_layout!(
          site_id: site.id,
          template: ~s(<body><main>{@inner_content}</main></body>)
        )

      {:ok, view, _html} =
        live(conn, "/admin/dashboard/runtime/builder/layout/#{layout.id}")

      _loaded = render_async(view)
      slot = view |> editor() |> Map.fetch!(:tree) |> Tree.walk() |> Enum.find(&(&1.kind == :eex))
      render_click(view, "op", %{"kind" => "delete", "node_id" => slot.id})

      group = view |> element(~s([data-problem-group="document"])) |> render()

      assert group =~ "This document"
      assert group =~ "nothing on this layout renders @inner_content"
    end
  end

  describe "a refused Publish" do
    test "says how many and what, and opens the same list", %{conn: conn, site: site} do
      {:ok, view, _html} = open_builder(conn, needy_page(site))

      refused = render_click(view, "publish", %{})

      assert refused =~
               "Not published — 2 problems: needful.src is required and empty; needful.:caption is required and empty. The red dot beside the status lists them."

      assert view |> element("#pb-problems-open-1") |> render() |> attribute("phx-mounted") =~
               "#pb-problems-modal"
    end

    test "names a single problem without a count", %{conn: conn, site: site} do
      needy(site.id)

      page =
        create_page!(
          site_id: site.id,
          template: ~s|<.component component_name="needful"><:caption>Hi</:caption></.component>|
        )

      {:ok, view, _html} = open_builder(conn, page)

      assert render_click(view, "publish", %{}) =~
               "Not published — needful.src is required and empty. The red dot beside the status lists it."
    end
  end

  defp attribute(html, name) do
    case Regex.run(~r/\s#{name}="([^"]*)"/, opening_tag(html)) do
      [_whole, value] -> value |> String.replace("&quot;", ~s(")) |> String.replace("&amp;", "&")
      nil -> ""
    end
  end
end
