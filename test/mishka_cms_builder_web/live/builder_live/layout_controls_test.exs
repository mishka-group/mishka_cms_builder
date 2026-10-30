# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.LayoutControlsTest do
  @moduledoc """
  The Inspector's Layout rows stay where they are while an author works through them.

  Choosing Row on a section adds Direction, Spread, Align and Wrap, and choosing Grid adds Columns.
  When those were drawn above Gap, the click that chose Row moved Gap four rows down, so the next
  click aimed at a gap preset landed on Direction. `Phoenix.LiveViewTest` has no layout engine, so
  what is pinned is the order the rows are drawn in, and the fixed height that keeps a heading from
  growing when its Reset appears.

  And a value set at Desktop can be taken off from its own row: Reset is drawn wherever the bucket
  holds the value, while the override dot stays away from Desktop, where nothing is overridden.
  """
  use MishkaCmsBuilder.LiveCase

  setup %{conn: conn, page: page} do
    {:ok, view, _html} = open_builder(conn, page)
    section = node_with_tag(view, "section")
    render_click(view, "select", %{"id" => section.id})
    view |> element("#pb-lefttab-inspector") |> render_click()

    %{view: view, node: section}
  end

  # The ids of the Layout group's controls, in the order the panel draws them.
  defp drawn_order(view, ids) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("[id]")
    |> LazyHTML.attribute("id")
    |> Enum.filter(&(&1 in ids))
  end

  # A row's heading is its first child.
  defp heading_classes(view, row) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("##{row} > div:first-child")
    |> LazyHTML.attribute("class")
    |> Enum.flat_map(&String.split/1)
  end

  test "choosing Row adds its rows under Gap, so Gap does not move", %{view: view} do
    rows = ~w(pb-style-pics-base-display pb-style-gap-base-None pb-style-pics-base-direction)

    view |> element("#pb-style-pic-base-display-flex") |> render_click()

    assert drawn_order(view, rows) == rows
  end

  test "choosing Grid adds Columns under Gap too", %{view: view} do
    rows = ~w(pb-style-pics-base-display pb-style-gap-base-None pb-style-cols-base)

    view |> element("#pb-style-pic-base-display-grid") |> render_click()

    assert drawn_order(view, rows) == rows
  end

  test "a Desktop value is reset from its own row", %{view: view, node: node} do
    refute has_element?(view, "#pb-style-clear-base-display")

    view |> element("#pb-style-pic-base-display-flex") |> render_click()

    assert has_element?(view, "#pb-style-clear-base-display")
    refute has_element?(view, "#pb-style-pics-base-display [title='Set for base']")

    view |> element("#pb-style-clear-base-display") |> render_click()

    assert styles_of(view, node.id) == %{}
    refute has_element?(view, "#pb-style-pics-base-direction")
  end

  test "the gap and the columns reset the same way", %{view: view, node: node} do
    view |> element("#pb-style-gap-base-L") |> render_click()
    view |> element("#pb-style-pic-base-display-grid") |> render_click()
    view |> element("#pb-style-cols-base-2") |> render_click()

    view |> element("#pb-style-clear-base-gap") |> render_click()
    view |> element("#pb-style-clear-base-grid-cols") |> render_click()

    assert styles_of(view, node.id) == %{base: %{"display" => "grid"}}
  end

  test "a heading keeps its height when its Reset appears", %{view: view} do
    view |> element("#pb-style-pic-base-display-flex") |> render_click()
    view |> element("#pb-style-gap-base-L") |> render_click()

    assert has_element?(view, "#pb-style-clear-base-display")
    assert has_element?(view, "#pb-style-clear-base-gap")

    for row <- ~w(pb-style-pics-base-display pb-style-gap-row-base) do
      assert "h-[19px]" in heading_classes(view, row), row
    end
  end
end
