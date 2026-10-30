# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.ControlNames do
  @moduledoc """
  One form-control name per independent drop, renumbered the way `MishkaCmsBuilder.Ids` renumbers
  an id.

  ## Why a second copy is a second control

  A palette entry arrives furnished, and a furnishing names its controls:
  `chelekom-headless-segmented-control` arrives as `name="period"`, Day, Week and Month. Its segments
  are radio buttons, and the browser groups radio buttons by name within one form, or within the
  page outside any form. Two dropped controls were therefore ONE group: choosing Month in the second
  cleared Week in the first, and only one of them ever showed a selection.

  ## Which names this touches

  Only a name a component renders on a form control — `name={@name}` on the `<input>`, `<select>` or
  `<textarea>` its own markup draws — and only a literal one. A component the kit calls a FIELD is
  left to `MishkaCmsCore.Runtime.Authoring.PageForms.FormPlacement`, which binds its name to the form
  it joins (`name={f[:period].name}`); a bound name is an expression and is never a candidate here
  either. `chelekom-icon`'s `name` is an icon and is left alone, because the icon's markup draws no
  control with it.

  ## The arrival yields, inside one form

  The same rule `Ids.dedupe/2` follows: `arrived` is what the op just created, and only those are
  renamed — the control already on the page keeps the name a handler may already read. A name is
  taken within its scope, the form around it or the page outside every form, which is where HTML
  groups radio buttons and where a submission collects its keys; the same name in two forms is two
  names. Arrivals that share a name share it on purpose — a worked example with a group in it — so
  they are renamed together, to one new name.

  Numbering fills gaps: `period` beside `period_3` gives `period_2`. The suffix follows a form key's
  spelling (`PageForms.Naming`'s `email_2`), and goes inside a trailing `[]` or `]` so `tags[]`
  becomes `tags_2[]`.
  """

  alias MishkaCmsCore.Runtime.Authoring.Fields
  alias MishkaCmsCore.Runtime.Authoring.Inspector
  alias MishkaCmsCore.Runtime.Authoring.PageForms
  alias MishkaCmsCore.Runtime.Authoring.Tree
  alias MishkaCmsCore.Runtime.Authoring.Tree.Node

  @doc """
  Renames each arrived component's literal control name that another control in the same scope
  already answers to. `components` is the palette, which says what each component renders.

  With nothing arrived there is nothing to rename: a document that came in whole is the author's
  own text.
  """
  @spec dedupe(Tree.t(), Enumerable.t(), [map()]) :: Tree.t()
  def dedupe(tree, arrived, components) do
    arrived = MapSet.new(arrived)

    case MapSet.size(arrived) do
      0 -> tree
      _some -> settle(tree, arrived, components || [])
    end
  end

  # Asked of the arrivals first, and of the whole page only when one of them brings a literal control
  # name: answering it parses each component's markup, and most drops bring none.
  defp settle(tree, arrived, components) do
    case tree |> nodes_in(arrived) |> named(components, %{}) do
      {[], _memo} -> tree
      {_some, memo} -> settle(tree, arrived, components, memo)
    end
  end

  defp settle(tree, arrived, components, memo) do
    roles = Fields.roles(Tree.walk(tree), components)
    {named, _memo} = tree |> Tree.walk() |> named(components, memo)

    named =
      Enum.map(named, fn {node_id, attr, name} ->
        {node_id, attr, scope(tree, node_id, roles), name}
      end)

    {arrivals, incumbents} =
      Enum.split_with(named, fn {node_id, _attr, _scope, _name} -> node_id in arrived end)

    taken = MapSet.new(incumbents, fn {_node_id, _attr, scope, name} -> {scope, name} end)

    arrivals
    |> Enum.filter(fn {node_id, _attr, _scope, _name} -> renamable?(tree, node_id, roles) end)
    |> Enum.group_by(fn {_node_id, _attr, scope, name} -> {scope, name} end)
    |> Enum.sort_by(fn {_key, [{node_id, _attr, _scope, _name} | _]} -> order(tree, node_id) end)
    |> Enum.reduce({tree, taken}, &claim/2)
    |> elem(0)
  end

  defp claim({{scope, name} = key, controls}, {tree, taken}) do
    case MapSet.member?(taken, key) do
      false ->
        {tree, MapSet.put(taken, key)}

      true ->
        new = free(name, scope, taken)

        renamed =
          Enum.reduce(controls, tree, fn {node_id, attr, _scope, _name}, acc ->
            write(acc, node_id, attr, new)
          end)

        {renamed, MapSet.put(taken, {scope, new})}
    end
  end

  defp nodes_in(tree, ids), do: ids |> Enum.map(&Tree.get(tree, &1)) |> Enum.reject(&is_nil/1)

  # Every literal control name on `nodes`, as `{node id, attribute, name}`: a raw control's own
  # `name`, and the attribute a component renders on its control. `memo` holds each component's
  # answer, so its markup is parsed once.
  defp named(nodes, components, memo) do
    Enum.flat_map_reduce(nodes, memo, fn node, memo ->
      {attrs, memo} = control_attrs(node, components, memo)

      names =
        for attr <- attrs,
            {:string, value} <- [Node.attr(node, attr)],
            name = String.trim(value),
            name != "",
            do: {node.id, attr, name}

      {names, memo}
    end)
  end

  defp control_attrs(%Node{kind: :tag} = node, _components, memo),
    do: {(PageForms.control?(node) && ["name"]) || [], memo}

  defp control_attrs(%Node{kind: :component} = node, components, memo) do
    name = Node.component_name(node)

    case memo do
      %{^name => attrs} ->
        {attrs, memo}

      %{} ->
        attrs = node |> Fields.entry(components) |> rendered_names()
        {attrs, Map.put(memo, name, attrs)}
    end
  end

  defp control_attrs(_node, _components, memo), do: {[], memo}

  # The attributes a component's own markup puts in a control's `name`: `name={@name}` on the
  # `<input type="radio">` of `chelekom-headless-segmented-control` names `name`.
  defp rendered_names(nil), do: []

  defp rendered_names(entry) do
    declared = entry |> Inspector.attrs() |> MapSet.new(&to_string(Inspector.name(&1)))

    with template when template != "" <- Inspector.template(entry),
         {:ok, markup} <- Tree.parse(template) do
      for node <- Tree.walk(markup),
          PageForms.control?(node),
          attr = node |> Node.attr("name") |> assign_name(),
          MapSet.member?(declared, attr),
          uniq: true,
          do: attr
    else
      _no_markup -> []
    end
  end

  defp assign_name({:expr, source}) do
    case Code.string_to_quoted(String.trim(source)) do
      {:ok, {:@, _meta, [{name, _var_meta, context}]}} when is_atom(name) and is_atom(context) ->
        Atom.to_string(name)

      _other ->
        nil
    end
  end

  defp assign_name(_other), do: nil

  # A raw control is the author's own markup, and a field is FormPlacement's to name.
  defp renamable?(tree, node_id, roles) do
    case Tree.get(tree, node_id) do
      %Node{kind: :component} = node -> not Fields.field_node?(node, roles)
      _other -> false
    end
  end

  # The form a control posts with, or the page outside every form.
  defp scope(tree, node_id, roles) do
    tree
    |> Tree.ancestors(node_id)
    |> Enum.find_value(:page, &(Fields.form_node?(&1, roles) && &1.id))
  end

  defp order(tree, node_id), do: Enum.find_index(Tree.walk(tree), &(&1.id == node_id))

  defp write(tree, node_id, attr, value) do
    case Tree.set_attr(tree, node_id, attr, {:string, value}) do
      {:ok, updated} -> updated
      {:error, _missing} -> tree
    end
  end

  defp free(name, scope, taken) do
    {stem, tail} = split(name)
    base = Regex.replace(~r/_\d+$/, stem, "")

    2
    |> Stream.iterate(&(&1 + 1))
    |> Stream.map(&"#{base}_#{&1}#{tail}")
    |> Enum.find(&(!MapSet.member?(taken, {scope, &1})))
  end

  # `tags[]` is the family `tags` with `[]` after it, and `user[email]` is `user[email` with `]`.
  defp split(name) do
    [_whole, stem, tail] = Regex.run(~r/^(.*?)(\]?(?:\[\])?)$/, name)
    {stem, tail}
  end
end
