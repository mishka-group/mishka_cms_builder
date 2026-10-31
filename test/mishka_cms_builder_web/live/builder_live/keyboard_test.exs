# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.KeyboardTest do
  @moduledoc """
  The keys that act on the selected element, and the search boxes that filter by what is typed.

  The browser half — which element the key names, and when a double click means the author is about
  to type — is `assets/test/pb_typing_keys.test.js`.
  """
  use MishkaCmsBuilder.LiveCase

  defp shortcut(view, key, params),
    do: render_click(view, "shortcut", Map.put(params, "key", key))

  defp present?(view, id), do: not is_nil(Tree.get(editor(view).tree, id))

  # AN E2E RUN LOST ITS HERO, ITS CALL-TO-ACTION AND ITS FOOTER TO BACKSPACE. The canvas rings an
  # element the moment it is clicked; the server's selection arrives a round trip later, and every
  # one of these keys read the server's. Pressed in between, Delete removed the element selected
  # before — not the one on screen.
  describe "a key acts on the element the author can see" do
    test "and on neither when the canvas rings one and the session holds another", %{
      conn: conn,
      page: page
    } do
      {:ok, view, _html} = open_builder(conn, page)
      h1 = node_with_tag(view, "h1")
      p = node_with_tag(view, "p")

      render_click(view, "select", %{"id" => h1.id})
      shortcut(view, "delete", %{"node_id" => p.id})

      assert present?(view, h1.id), "the element the server held was deleted"
      assert present?(view, p.id)
      assert flashes(view) =~ "had not caught up"
    end

    test "deletes the one it names when the session agrees, as one undoable step", %{
      conn: conn,
      page: page
    } do
      {:ok, view, _html} = open_builder(conn, page)
      p = node_with_tag(view, "p")

      render_click(view, "select", %{"id" => p.id})
      shortcut(view, "delete", %{"node_id" => p.id})

      refute present?(view, p.id)
      assert %{label: "Deleted element"} = hd(editor(view).past)

      undo!(view)
      assert node_with_tag(view, "p")
    end

    # Nothing ringed, or a ring left on the element the last key already took: either way the author
    # can see nothing selected, so the key has nothing to act on — not whatever the server holds.
    test "and deletes nothing when it names nothing, or names an element already gone", %{
      conn: conn,
      page: page
    } do
      {:ok, view, _html} = open_builder(conn, page)
      h1 = node_with_tag(view, "h1")
      p = node_with_tag(view, "p")
      before = node_count(view)

      render_click(view, "select", %{"id" => h1.id})
      shortcut(view, "delete", %{"node_id" => nil})
      assert node_count(view) == before
      assert flashes(view) =~ "Select an element on the page first."

      render_click(view, "select", %{"id" => p.id})
      shortcut(view, "delete", %{"node_id" => p.id})
      clear_flashes(view)

      shortcut(view, "delete", %{"node_id" => p.id})
      assert present?(view, h1.id)
      assert flashes(view) =~ "Select an element on the page first."
      refute flashes(view) =~ "no longer on the page"
    end

    test "cut, copy and duplicate follow the same rule", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)
      h1 = node_with_tag(view, "h1")
      p = node_with_tag(view, "p")
      before = node_count(view)

      render_click(view, "select", %{"id" => h1.id})

      for key <- ~w(cut duplicate copy) do
        shortcut(view, key, %{"node_id" => p.id})
        assert node_count(view) == before, key
      end

      assert is_nil(editor(view).clipboard), "copy took the element the author was not looking at"

      shortcut(view, "duplicate", %{"node_id" => h1.id})
      assert length(Enum.filter(Tree.walk(editor(view).tree), &(&1.tag == "h1"))) == 2
    end

    # A DOUBLE CLICK THAT OPENED NO WORDS. The author is typing as far as they know, and Backspace is
    # the first key they reach for.
    test "and removes nothing while the author believes they are typing", %{
      conn: conn,
      page: page
    } do
      {:ok, view, _html} = open_builder(conn, page)
      h1 = node_with_tag(view, "h1")

      render_click(view, "select", %{"id" => h1.id})

      for key <- ~w(delete cut) do
        shortcut(view, key, %{"node_id" => h1.id, "typing" => true})
        assert present?(view, h1.id), key
      end

      assert flashes(view) =~ "Nothing was removed: no text is being edited."
    end

    # The chrome's own keys — a Backspace with a layers row focused — name what the chrome last drew.
    test "the chrome carries the selection it drew for its own keys to name", %{
      conn: conn,
      page: page
    } do
      {:ok, view, _html} = open_builder(conn, page)
      h1 = node_with_tag(view, "h1")

      refute has_element?(view, "#pb-root[data-selection]")

      render_click(view, "select", %{"id" => h1.id})
      assert has_element?(view, ~s(#pb-root[data-selection="#{h1.id}"]))
    end
  end

  # A SEARCH THAT ONLY HEARD A KEY COMING UP. Text that arrives without one — pasted from the menu,
  # dropped, filled in by the browser — never reached the server, so the list stayed unfiltered under
  # a box that said otherwise, and the X then pushed the empty query the server already had: nothing
  # changed, so nothing cleared the box.
  describe "a search box" do
    test "the palette's follows a change, however the text arrived, and its X clears it", %{
      conn: conn,
      page: page
    } do
      {:ok, view, _html} = open_builder(conn, page)

      view |> form("#pb-palette-search-form", %{"value" => "zzzznothing"}) |> render_change()
      assert live_assigns(view).palette_query == "zzzznothing"
      assert view |> element("#pb-palette-search") |> render() =~ ~s(value="zzzznothing")

      view |> element(~s([data-for="pb-palette-search"])) |> render_click()
      assert live_assigns(view).palette_query == ""
      assert view |> element("#pb-palette-search") |> render() =~ ~s(value="")
    end

    test "and so does the command palette's", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)
      render_click(view, "toggle_command", %{})

      view |> form("#pb-command-form", %{"value" => "undo"}) |> render_change()
      assert live_assigns(view).command_query == "undo"

      view |> element(~s([data-for="pb-command-input"])) |> render_click()
      assert live_assigns(view).command_query == ""
    end

    test "and the component registry's", %{conn: conn, page: page} do
      Application.put_env(:mishka_cms_builder, :marketplace, MishkaCmsBuilder.Marketplace.Mock)
      on_exit(fn -> Application.delete_env(:mishka_cms_builder, :marketplace) end)

      {:ok, view, _html} = open_builder(conn, page)
      render_click(view, "open_sheet", %{"sheet" => "studio"})
      _studio = render_async(view, 5_000)
      view |> element("#pb-studio-registry") |> render_click()

      view |> form("#pb-registry-search-form", %{"value" => "charts"}) |> render_change()
      refute has_element?(view, "#pb-pkg-chelekom-datatable")
      assert has_element?(view, "#pb-pkg-chelekom-charts")

      view |> element(~s([data-for="pb-registry-search"])) |> render_click()
      assert has_element?(view, "#pb-pkg-chelekom-datatable")
    end
  end

  # ESCAPE IN A MODAL HAS ONE OWNER. Each modal below closes on its own `phx-window-keydown`, and
  # the keyboard hook stays out of escape while an element marked `data-pb-modal` is on the page
  # (`assets/test/pb_modal_escape.test.js`). A modal drawn without the mark heard escape twice, and
  # the hook's push left the modal's backdrop over the editor, blocking every click.
  describe "a modal that closes itself on escape" do
    defp marked?(view, id, event),
      do: has_element?(view, ~s(##{id}[data-pb-modal][phx-window-keydown="#{event}"]))

    test "the Code window and Find carry the mark", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)

      view |> element("#pb-code") |> render_click()
      assert marked?(view, "pb-source-modal", "close_source")
      view |> element("#pb-source-close") |> render_click()

      render_click(view, "open_find", %{})
      assert marked?(view, "pb-find", "close_find")
    end

    test "so do the reload and leave questions", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)
      render_click(view, "set_stage", %{"stage" => "published"})
      render_click(view, "op", %{"kind" => "delete", "node_id" => node_with_tag(view, "p").id})

      view |> element("#pb-reload") |> render_click()
      assert marked?(view, "pb-reload-modal", "close_reload")
      view |> element("#pb-reload-cancel") |> render_click()

      render_click(view, "leaving", %{"to" => "/admin/dashboard/runtime/pages"})
      assert marked?(view, "pb-leave-modal", "stay")
    end

    test "and the new-folder form, drawn inside the Media sheet", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)
      render_click(view, "open_sheet", %{"sheet" => "assets"})
      render_async(view)

      render_click(view, "new_folder", %{})
      assert marked?(view, "pb-folder-modal", "close_folder")
    end

    # Under the Media sheet its SEO tab opened, Settings binds no escape: the sheet is the one to
    # close, and that is the editor's `shortcut("escape", …)`, so the hook must not stand back.
    test "Settings carries it only while nothing is over it", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)
      view |> element("#pb-settings-open") |> render_click()
      _settled = render_async(view)
      assert marked?(view, "pb-settings-modal", "close_settings")

      view |> element("#pb-settings-tab-seo") |> render_click()
      _settled = render_async(view)
      view |> element("#pb-seo-image-pick") |> render_click()

      assert has_element?(view, "#pb-settings-modal.hidden")
      refute has_element?(view, "[data-pb-modal]")
    end

    test "and the command palette, which the editor's escape closes, does not", %{
      conn: conn,
      page: page
    } do
      {:ok, view, _html} = open_builder(conn, page)

      render_click(view, "toggle_command", %{})
      assert has_element?(view, "#pb-command")
      refute has_element?(view, "[data-pb-modal]")

      render_click(view, "shortcut", %{"key" => "escape"})
      refute has_element?(view, "#pb-command")
    end
  end
end
