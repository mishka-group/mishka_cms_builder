# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.StrictTest do
  @moduledoc """
  The editor's half of `MishkaCmsCore.Runtime.Authoring.Strict`: every edit the session applies
  leaves a document the checks accept, so the funnel that turns a silent wrong answer into a loud
  one never fires on an ordinary edit.
  """
  use ExUnit.Case, async: true

  alias MishkaCmsCore.Runtime.Authoring.Strict
  alias MishkaCmsCore.Runtime.Authoring.Tree

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
