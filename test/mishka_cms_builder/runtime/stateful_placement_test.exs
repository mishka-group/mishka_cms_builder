# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Runtime.StatefulPlacementTest do
  @moduledoc """
  The editor's half of the duplicate-id rule for live components.

  A page refuses two live components under one `id`, because `Phoenix.LiveView.Diff` raises
  "found duplicate ID … for component …" inside whichever LiveView renders it. The page asks that
  of the stored markup, and the core suite pins the refusal. The editor's own minting does not cover
  it — `Ids.dedupe/2` renames the nodes that ARRIVED and answers nothing when a whole document
  arrives at once — but it has to keep an author from ever meeting that refusal by the ordinary way
  of getting a second of anything, which is duplicating one.
  """
  use ExUnit.Case, async: true

  alias MishkaCmsBuilder.Ids
  alias MishkaCmsCore.Runtime.Authoring.Tree

  @moduletag :unit

  defp twice(name, id_one, id_two) do
    ~s(<div><.component component_name="#{name}" site="Global" id="#{id_one}" />) <>
      ~s(<.component component_name="#{name}" site="Global" id="#{id_two}" /></div>)
  end

  describe "two live components under one id" do
    # AND AN AUTHOR SHOULD NEVER MEET THAT REFUSAL BY DUPLICATING ONE, which is the ordinary way to
    # get a second of anything. `Tree.duplicate/2` copies every attribute verbatim, so the copy
    # arrives wearing the original's id; `Ids.dedupe/2` renames the node that ARRIVED and leaves the
    # one already placed alone. Nothing about that mechanism is specific to live components — which
    # is exactly why it is pinned here, where getting it wrong means a save the author cannot
    # complete rather than two buttons opening one dialog.
    test "a duplicate arrives with an id of its own, so the rule is never met" do
      {:ok, tree} = Tree.parse(twice("live-widget", "phx-F8kQ2n1aRxY", "phx-F8kQ2n1aRxY"))

      [_original, copy] = Tree.walk(tree) |> Enum.filter(&(&1.kind == :component))

      ids =
        tree
        |> Ids.dedupe([copy.id])
        |> Tree.walk()
        |> Enum.filter(&(&1.kind == :component))
        |> Enum.map(&Tree.Node.attr(&1, "id"))

      assert [{:string, "phx-F8kQ2n1aRxY"}, {:string, fresh}] = ids

      assert fresh != "phx-F8kQ2n1aRxY",
             "the copy kept the original's id — every duplicate would be a save the author cannot complete"
    end
  end
end
