# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.CanvasInlineBoxTest do
  @moduledoc """
  The editor's box around a component does not break the line it stands in.

  The canvas wraps every kit and function component in an element carrying its id, its drag handle
  and its click target. That element was always a `<div>`, and a `<div>` inside a `<p>` is markup
  the parser answers by closing the paragraph in front of it: a button dropped onto a paragraph
  saved the right markup, and the canvas drew an empty `<p>` and the paragraph's words as a node of
  their own at the root of the page. The published page has no box, so it was whole.

  Where the element a component stands in holds words only, the box is a `<span>`, which the parser
  keeps inside it. The element is read the way core's `Containment` reads it: a tag is itself, and a
  kit component is the element its markup renders its content in. Anywhere else the box stays a
  `<div>`.
  """
  use MishkaCmsBuilder.LiveCase

  setup %{site: site} do
    create_component!(
      site_id: site.id,
      name: "pb-pill",
      template: ~S|<button type="button" class="pill">{render_slot(@inner_block)}</button>|
    )

    create_component!(
      site_id: site.id,
      name: "pb-kit-p",
      template: ~S|<p class="kit-p">{render_slot(@inner_block)}</p>|
    )

    create_component!(
      site_id: site.id,
      name: "pb-card",
      template: ~S|<div class="card">{render_slot(@inner_block)}</div>|
    )

    :ok
  end

  defp canvas_html(conn, site, template) do
    page = create_page!(site_id: site.id, template: template)
    {:ok, view, _html} = open_builder(conn, page)
    {:ok, _canvas, html} = live(conn, "/admin/dashboard/runtime/builder-canvas/#{token(view)}")
    html
  end

  defp parsed(html, selector),
    do: html |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

  defp pill(site, words),
    do: ~s(<.component component_name="pb-pill" site="#{site.name}">#{words}</.component>)

  describe "a component in a paragraph" do
    test "is boxed in a span, so the paragraph keeps its words", %{conn: conn, site: site} do
      html =
        canvas_html(
          conn,
          site,
          ~s(<p id="intro" class="p-6">#{pill(site, "Get started")}Some paragraph words</p>)
        )

      assert Enum.count(parsed(html, "p")) == 1, "the paragraph is not closed in front of the box"
      assert html =~ ~r/<p[^>]*id="intro"[^>]*><span[^>]*data-pb-frame="true"/

      [intro] = parsed(html, "p#intro > span[data-pb-frame] > button.pill") |> Enum.to_list()
      assert LazyHTML.text(intro) == "Get started"

      assert parsed(html, "p#intro") |> LazyHTML.text() =~ "Some paragraph words"
      refute html =~ "phx-no-format"
    end

    test "inside a link in a paragraph is boxed in a span too", %{conn: conn, site: site} do
      html =
        canvas_html(
          conn,
          site,
          ~s(<p id="intro"><a id="more" href="/more">#{pill(site, "Read")}</a> after</p>)
        )

      assert Enum.count(parsed(html, "p")) == 1
      assert Enum.count(parsed(html, "p#intro a#more > span[data-pb-frame]")) == 1
    end

    test "inside a kit paragraph is boxed in a span, read off the kit's own markup", %{
      conn: conn,
      site: site
    } do
      html =
        canvas_html(
          conn,
          site,
          ~s(<div id="page"><.component component_name="pb-kit-p" site="#{site.name}">) <>
            ~s(#{pill(site, "Go")}words after</.component></div>)
        )

      assert Enum.count(parsed(html, "p")) == 1
      assert Enum.count(parsed(html, "div#page > div[data-pb-frame] > p.kit-p")) == 1
      assert Enum.count(parsed(html, "p.kit-p > span[data-pb-frame] > button.pill")) == 1
      assert parsed(html, "p.kit-p") |> LazyHTML.text() =~ "words after"
    end

    test "that needs a field it has not been given is boxed in a span too", %{
      conn: conn,
      site: site
    } do
      create_component!(
        site_id: site.id,
        name: "pb-needy",
        template: ~S|<button type="button">{@label}</button>|,
        attrs: [%{"name" => "label", "type" => "string", "opts" => %{"required" => true}}]
      )

      html =
        canvas_html(
          conn,
          site,
          ~s(<p id="intro"><.component component_name="pb-needy" site="#{site.name}" />words</p>)
        )

      assert Enum.count(parsed(html, "p")) == 1
      assert Enum.count(parsed(html, "p#intro > span[data-incomplete]")) == 1
    end
  end

  # An inline box ignores `min-height` and `width`, which is all the floor of an empty component, the
  # media well and the hollow of an empty container are made of.
  test "a box in a line keeps the floor and the wells an empty one is drawn with", %{
    conn: conn,
    site: site
  } do
    html = canvas_html(conn, site, ~s(<p id="intro">#{pill(site, "Go")}</p>))

    chrome = html |> parsed("style#pb-canvas-chrome") |> LazyHTML.text()

    for state <- ~w(data-pb-blank data-wants-media data-pb-hollow) do
      assert chrome =~ "span[data-pb-frame][#{state}]"
    end

    assert chrome =~ ~r/span\[data-pb-frame\]\[data-pb-hollow\]\s*\{\s*display:\s*inline-block/
  end

  describe "a component anywhere else" do
    test "keeps its box a div", %{conn: conn, site: site} do
      html =
        canvas_html(
          conn,
          site,
          ~s(<div id="row">#{pill(site, "Plain")}</div>) <>
            ~s(<.component component_name="pb-card" site="#{site.name}">#{pill(site, "Inner")}</.component>)
        )

      assert Enum.count(parsed(html, "div#row > div[data-pb-frame] > button.pill")) == 1
      assert Enum.count(parsed(html, "div.card > div[data-pb-frame] > button.pill")) == 1
      assert Enum.empty?(parsed(html, "span[data-pb-frame]"))
    end
  end
end
