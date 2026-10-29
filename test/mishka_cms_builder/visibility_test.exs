# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.VisibilityTest do
  @moduledoc """
  `MishkaCmsCore.Runtime.Authoring.Visibility`: an element kept in the page and shown to nobody —
  the marker in the markup, what the compilers leave out, and the one edit that toggles it.
  """
  use ExUnit.Case, async: true

  alias MishkaCmsBuilder.EditorSession
  alias MishkaCmsCore.Runtime.Authoring.Visibility
  alias MishkaCmsCore.Runtime.Authoring.Tree
  alias MishkaCmsCore.Runtime.Authoring.Tree.Serializer

  defp node(tree, tag), do: Enum.find(Tree.walk(tree), &(&1.tag == tag))

  describe "the edit" do
    test "hides an element, shows it again, and each is one entry in the history, undone as one" do
      {:ok, session} =
        EditorSession.open(%{section: "page", template: ~S(<div><p>Hello</p></div>)})

      p = node(session.tree, "p")

      {:ok, hidden} = EditorSession.toggle_visibility(session.token, p.id)
      assert Visibility.hidden?(Tree.get(hidden.tree, p.id))
      assert Serializer.serialize(hidden.tree) =~ "<p data-pb-hidden>Hello</p>"
      assert %{label: "Hidden from visitors"} = hd(hidden.past)

      {:ok, shown} = EditorSession.toggle_visibility(session.token, p.id)
      refute Visibility.hidden?(Tree.get(shown.tree, p.id))
      assert %{label: "Shown to visitors"} = hd(shown.past)

      {:ok, undone} = EditorSession.undo(session.token)
      assert Visibility.hidden?(Tree.get(undone.tree, p.id))
    end

    test "is refused for text, and for an element hidden only because its container is" do
      {:ok, session} =
        EditorSession.open(%{
          section: "page",
          template: ~S(<section data-pb-hidden><h2>Title</h2>words</section>)
        })

      text = Enum.find(Tree.walk(session.tree), &(&1.kind == :text and &1.text =~ "words"))
      h2 = node(session.tree, "h2")

      assert {:error, "Only an element can be hidden." <> _} =
               EditorSession.toggle_visibility(session.token, text.id)

      assert {:error, "It is hidden with the element around it." <> _} =
               EditorSession.toggle_visibility(session.token, h2.id)
    end

    test "is the right-click menu's visibility entry" do
      {:ok, session} =
        EditorSession.open(%{section: "page", template: ~S(<div><p>Hello</p></div>)})

      p = node(session.tree, "p")

      assert {:ok, hidden} = EditorSession.context_action(session.token, "visibility", p.id)
      assert Visibility.hidden?(Tree.get(hidden.tree, p.id))
    end
  end
end
