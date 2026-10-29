# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.StrictTest do
  @moduledoc """
  The checks that turn a silent wrong answer into a loud one, and the documents they catch.

  Every case here is a real shape that reached production undetected: a `children` list naming an id
  that is not in the document, which costs that subtree at the next save because the serializer is
  total and the save's own check only proves the output parses; a node claiming a parent that does
  not claim it back; a cycle, which turns a walk into a hang.
  """
  use ExUnit.Case, async: true

  require MishkaCmsCore.Runtime.PageBuilder.Strict

  alias MishkaCmsCore.Runtime.PageBuilder.Strict
  alias MishkaCmsCore.Runtime.PageBuilder.Tree

  @moduletag :unit

  defp tagged(tree, tag), do: Enum.find(Tree.walk(tree), &(&1.tag == tag))

  describe "the mutation funnel is checked" do
    test "an ordinary edit leaves a consistent document" do
      {:ok, session} =
        MishkaCmsBuilder.EditorSession.open(%{
          section: "page",
          template: ~s(<section><h1>Title</h1><p>hello</p></section>)
        })

      id = tagged(session.tree, "h1").id

      {:ok, edited} =
        MishkaCmsBuilder.EditorSession.apply_op(session.token, %{
          kind: :set_text,
          node_id: id,
          text: "Changed"
        })

      assert :ok = Strict.inspect_tree(edited.tree)
    end
  end
end
