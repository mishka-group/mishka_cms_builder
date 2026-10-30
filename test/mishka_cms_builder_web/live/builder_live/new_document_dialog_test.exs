# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.NewDocumentDialogTest do
  @moduledoc """
  "+ Add Page" opens the editor on a dialog, and the dialog says it is one.

  The editor is the whole page behind it, so without the dialog's role a screen reader was handed
  every palette card and canvas tool beside the three fields that are the only thing to do. The
  box is a modal dialog named by its heading and described by the line under it, and its first
  field takes the focus when it opens.
  """
  use MishkaCmsBuilder.LiveCase

  test "the box is a modal dialog named by its heading", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/dashboard/runtime/builder/page")

    dialog =
      "#pb-new-document section[role=dialog][aria-modal=true]" <>
        "[aria-labelledby=pb-new-document-title][aria-describedby=pb-new-document-note]"

    assert has_element?(view, dialog)
    assert has_element?(view, "#{dialog} h2#pb-new-document-title", "Name your page")
    assert has_element?(view, "#{dialog} #pb-new-document-note")
  end

  test "it opens with the focus on its form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/dashboard/runtime/builder/page")

    [mounted] =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#pb-new-document")
      |> LazyHTML.attribute("phx-mounted")

    assert mounted =~ ~s(["focus_first",{"to":"#pb-new-document form"}])
  end
end
