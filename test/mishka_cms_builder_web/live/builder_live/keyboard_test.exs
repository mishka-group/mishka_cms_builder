# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.KeyboardTest do
  @moduledoc """
  The keys that act on the selected element.

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
end
