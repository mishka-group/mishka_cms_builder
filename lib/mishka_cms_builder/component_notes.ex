# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.ComponentNotes do
  @moduledoc """
  What the extensions tell the author about one placed component, read for the editor's three
  places that show it: the canvas (a badge on the component's frame), the Inspector (a box under
  the selection's head) and the Audit rail (the Content group).

  The notes come from `MishkaCmsCore.Builder.Events.component_notes/1`, the
  `builder:component:notes` event: a product block whose product was archived, a list pointed at
  something that is gone. A plugin is asked with the component's name, its literal attributes
  (`attrs/1`), the node's id and the site. Only the editor asks, so a published page never pays for
  it and a visitor never sees a note.

  ## One ask for the same block

  A plugin usually reads something to judge a block, and the panels and the canvas draw again on
  every keystroke. So an answer is kept in the asking process for a few seconds under what was asked
  (the component, its attributes and the site; never the node's id, which a re-parse mints again):
  two identical blocks, the Inspector and the Audit rail of one render, and the renders of a burst of
  typing share one ask. A changed attribute is a different question and is asked at once. `forget/0`
  drops the kept answers, which is what the Audit rail's Re-run does.
  """

  alias MishkaCmsCore.Builder.Events
  alias MishkaCmsCore.Runtime.Authoring.Tree.Node

  @memo {__MODULE__, :asked}
  @fresh_ms 5_000

  @typedoc "One note, as `MishkaCmsCore.Builder.Events.component_notes/1` answers it."
  @type note :: %{severity: :warning | :note, message: String.t(), detail: String.t() | nil}

  @doc """
  The notes of `node` when it is a component, else `[]`. `scope` names the site: `:site_id` and
  `:site_name`, either of which may be `nil` (a layout or a component of no site).
  """
  @spec for_node(Node.t() | nil, map()) :: [note()]
  def for_node(%Node{kind: :component} = node, scope) do
    case Node.component_name(node) do
      name when is_binary(name) and name != "" ->
        question = %{
          component: name,
          attrs: attrs(node),
          site_id: scope[:site_id],
          site_name: scope[:site_name]
        }

        asked(question, node.id)

      _unnamed ->
        []
    end
  end

  def for_node(_node, _scope), do: []

  @doc """
  The component's attributes an extension can judge: each literal value by its name as written (a
  string, `true` for a bare attribute, and `true`, `false` or a number written as an expression).
  Any other expression is left out, because the editor cannot know what it holds on a page, and so
  is `component_name`, which is the component itself.
  """
  @spec attrs(Node.t()) :: %{String.t() => String.t() | boolean() | number()}
  def attrs(%Node{attrs: attrs}) do
    for {name, value} <- attrs,
        is_binary(name) and name != "component_name",
        {:ok, literal} <- [literal(value)],
        into: %{},
        do: {name, literal}
  end

  @doc "Drops the answers this process kept, so the next ask goes to the extensions again."
  @spec forget() :: :ok
  def forget do
    Process.delete(@memo)
    :ok
  end

  defp literal({:string, value}), do: {:ok, value}
  defp literal(:boolean), do: {:ok, true}
  defp literal({:expr, source}), do: source |> String.trim() |> expression()
  defp literal(_other), do: :skip

  defp expression("true"), do: {:ok, true}
  defp expression("false"), do: {:ok, false}

  defp expression(source) do
    case {Integer.parse(source), Float.parse(source)} do
      {{number, ""}, _float} -> {:ok, number}
      {_integer, {number, ""}} -> {:ok, number}
      _not_a_number -> :skip
    end
  end

  defp asked(question, node_id) do
    now = System.monotonic_time(:millisecond)
    kept = Process.get(@memo, %{})

    case kept do
      %{^question => {notes, at}} when now - at < @fresh_ms ->
        notes

      _stale_or_new ->
        notes = Events.component_notes(Map.put(question, :node_id, node_id))
        fresh = for {key, {_notes, at} = answer} <- kept, now - at < @fresh_ms, into: %{}, do: {key, answer}
        Process.put(@memo, Map.put(fresh, question, {notes, now}))
        notes
    end
  end
end
