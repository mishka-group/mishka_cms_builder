# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.DarkThemeTest do
  @moduledoc """
  The dark theme darkens the editor, not the page being edited.

  The theme is one filter on `#pb-root`, and a filter reaches into every iframe drawn under it. So a
  frame that shows a document carries the inverse filter, or the document arrives on screen inverted:
  a section set to `#f2f1ec` was drawn near-black, while the kit's components, which answer the
  frame's own `data-theme="dark"`, came out light under the same filter.

  `Phoenix.LiveViewTest` paints nothing, so what is pinned is that each frame showing a document
  wears the inverse, and that the inverse is the root's filter undone for the amount the root sets.
  """
  use MishkaCmsBuilder.LiveCase

  @frame_filter "[[data-theme=dark]_&]:[filter:hue-rotate(180deg)_invert(1)_contrast(1.1905)]"

  defp root_filter,
    do: ~r/^\[\[data-theme=dark\]_&\]:\[filter:invert\(([\d.]+)\)_hue-rotate\(180deg\)\]$/

  defp classes(view, selector) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query(selector)
    |> LazyHTML.attribute("class")
    |> Enum.flat_map(&String.split/1)
  end

  test "the canvas shows the document as it renders, at every width", %{conn: conn, page: page} do
    {:ok, view, _html} = open_builder(conn, page)

    assert @frame_filter in classes(view, "#pb-frame-desktop")

    view |> element("#pb-device-frames") |> render_click()

    for width <- [1180, 900, 560] do
      assert @frame_filter in classes(view, "#pb-frame-#{width}"), "the #{width}px frame"
    end
  end

  test "so does the preview a palette card opens", %{conn: conn, page: page} do
    {:ok, view, _html} = open_builder(conn, page)

    assert @frame_filter in classes(view, "[data-role=pb-card-preview-frame]")
  end

  # THE INVERSE OF THE AMOUNT THE ROOT SETS, not of a number copied beside it. `invert(p)` maps a tone
  # `x` to `p + (1 - 2p) x`; `invert(1)` then `contrast(c)` maps it back when `c = 1 / (2p - 1)`, and
  # `hue-rotate(180deg)` is its own inverse. Change the root's amount and this says the frames no
  # longer undo it.
  test "the frame's filter undoes the root's", %{conn: conn, page: page} do
    {:ok, view, _html} = open_builder(conn, page)

    [amount] =
      for class <- classes(view, "#pb-root"),
          [_, amount] <- Regex.scan(root_filter(), class),
          do: String.to_float(amount)

    [contrast] =
      Regex.run(~r/contrast\(([\d.]+)\)/, @frame_filter, capture: :all_but_first)

    root = fn x -> amount + (1 - 2 * amount) * x end
    frame = fn x -> String.to_float(contrast) * (1 - x - 0.5) + 0.5 end

    for tone <- [0.1, 0.25, 0.5, 0.75, 0.9] do
      assert_in_delta root.(frame.(tone)), tone, 0.001
    end
  end
end
