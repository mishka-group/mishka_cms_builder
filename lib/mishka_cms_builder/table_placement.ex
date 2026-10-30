# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.TablePlacement do
  @moduledoc """
  Puts a table around a cell, a row or a table section dropped where no table holds it.

  A parser ignores a `<td>` written outside a table, so the core refuses one there
  (`MishkaCmsCore.Runtime.Authoring.Containment`). Refused and nothing else, a Table cell card
  dropped on a page would do nothing at all, and an author who wanted a table would have to know to
  start from the Table card. The drop that FormPlacement answers for a field — wrap it in what it
  needs, and say so — is the same gesture here: the part arrives inside the smallest table structure
  its landing place takes, as one insert and one undo step.

  ## What it is wrapped in

  A kit's own part gets the kit's own row and table, found by their markup rather than by name: a
  component whose markup opens with a `<tr>` and renders its content in it is a row, and one that
  renders its content in a `<tbody>` or a `<table>` is a table. The kit's cell is styled by the kit's
  table, so a bare `<table>` around it would look like a different component. A raw part, or a kit
  with no row or table of its own, gets plain `<tr>`, `<tbody>` and `<table>` tags.

  Only as much as the landing place needs: a cell dropped into a table section gets a row, a cell
  dropped on a page gets a row and a table.

  ## Moves are not wrapped

  A cell dragged out of its row is refused and climbs back to where a cell may go, as any refused
  move does. Wrapping is for a part arriving from the palette.
  """

  use Gettext, backend: MishkaCmsCore.Gettext

  alias MishkaCmsBuilder.PaletteEntry
  alias MishkaCmsCore.Runtime.Authoring.Containment
  alias MishkaCmsCore.Runtime.Authoring.Section
  alias MishkaCmsCore.Runtime.Authoring.Tree
  alias MishkaCmsCore.Runtime.Authoring.Tree.Node

  @typedoc "Whether a placement put a table around what arrived."
  @type outcome :: :none | :tabled

  # What a part is wrapped in, innermost first, up to the table.
  @levels %{
    "td" => ~w(tr tbody table),
    "th" => ~w(tr thead table),
    "tr" => ~w(tbody table),
    "thead" => ~w(table),
    "tbody" => ~w(table),
    "tfoot" => ~w(table),
    "caption" => ~w(table),
    "colgroup" => ~w(table),
    "col" => ~w(colgroup table)
  }

  @sections ~w(thead tbody tfoot)

  @doc "What the author is told after a placement, or `nil` when there is nothing to say."
  @spec told(outcome()) :: String.t() | nil
  def told(:tabled),
    do: gettext("A table part shows only inside a table, so it arrived in a new one.")

  def told(_outcome), do: nil

  @doc """
  Whether a component's own markup is a fragment placed elsewhere later, whose top level may hold a
  table part: the `fragment?` option `Containment.can_drop?/4` takes.
  """
  @spec fragment?(map()) :: boolean()
  def fragment?(%{section: section}) when is_binary(section) or is_atom(section),
    do: Section.normalize(section) == "component"

  def fragment?(_session), do: false

  @doc """
  The template to insert at `parent` (a node id, `"root"` or `:root`), and whether a table was put
  around it.

  Untouched when its first element is not a table part, or when `parent` already holds it.
  Otherwise it is wrapped in the first of its possible wrappers that `parent` takes, or in the whole
  table when none is — which a refused drop then carries as it climbs.
  """
  @spec wrap(String.t(), map(), String.t() | :root | nil) :: {String.t(), outcome()}
  def wrap(template, session, parent) do
    opts = opts(session)

    with {:ok, tree} <- Tree.parse(template),
         %Node{} = head <- head(tree),
         [_ | _] = chains <- chains(head, session, opts),
         {:error, _refused} <- fits(session, head, tree, parent, opts) do
      {fitted(template, chains, site(head), session, parent, opts), :tabled}
    else
      _at_home -> {template, :none}
    end
  end

  @doc """
  The heads a table part could arrive as — the part itself and every wrapper it may be given — each
  with its own tree. A drag asks every one of them where it may land (`drop_hints`), because the
  drop puts the wrapper around it there. `[]` for anything that is not a table part.
  """
  @spec arrivals(String.t(), map()) :: [{Node.t(), Tree.t()}]
  def arrivals(template, session) do
    opts = opts(session)

    with {:ok, tree} <- Tree.parse(template),
         %Node{} = head <- head(tree),
         [_ | _] = chains <- chains(head, session, opts) do
      Enum.flat_map(chains, &arrival(wrapped(template, &1, site(head), session)))
    else
      _not_a_part -> []
    end
  end

  defp arrival(template) do
    case Tree.parse(template) do
      {:ok, tree} -> [{head(tree), tree}]
      _unparsed -> []
    end
  end

  defp opts(session),
    do: [components: Map.get(session, :components, []), fragment?: fragment?(session)]

  defp head(%Tree{roots: roots} = tree) do
    roots
    |> Enum.map(&Tree.get(tree, &1))
    |> Enum.find(&match?(%Node{kind: kind} when kind in [:tag, :component], &1))
  end

  defp fits(session, head, tree, parent, opts),
    do:
      Containment.can_drop?(session.tree, head, parent_ref(parent), [dragged_tree: tree] ++ opts)

  defp parent_ref(nil), do: :root
  defp parent_ref("root"), do: :root
  defp parent_ref(parent), do: parent

  # The first wrapper `parent` takes, or the whole table.
  defp fitted(template, chains, site, session, parent, opts) do
    wrappers = Enum.map(chains, &wrapped(template, &1, site, session))

    Enum.find(wrappers, List.last(wrappers), fn wrapper ->
      with {:ok, tree} <- Tree.parse(wrapper),
           %Node{} = head <- head(tree) do
        fits(session, head, tree, parent, opts) == :ok
      else
        _unparsed -> false
      end
    end)
  end

  # Every wrapper a part may be given, smallest first, each a list of levels innermost first. A
  # level is a tag or a kit component's palette entry.
  defp chains(head, session, opts) do
    with tag when is_binary(tag) <- Containment.element(head, opts),
         [_ | _] = levels <- Map.get(@levels, tag) do
      levels
      |> kit_levels(head, Map.get(session, :components, []))
      |> prefixes()
    else
      _not_a_part -> []
    end
  end

  defp prefixes(levels), do: for(n <- 1..length(levels)//1, do: Enum.take(levels, n))

  # A kit's own part is put in the kit's own row and table; the table stands for every level from
  # the section up, because its markup draws the section itself.
  defp kit_levels(levels, %Node{kind: :component} = head, components) do
    prefix = kit_prefix(Node.component_name(head))
    row = holder(components, prefix, &(&1 == {"tr", "tr"}))
    table = holder(components, prefix, fn {_opens, holds} -> holds in ["tbody", "table"] end)

    levels
    |> Enum.map(&kit_level(&1, row))
    |> collapse(table)
  end

  defp kit_levels(levels, _head, _components), do: levels

  defp kit_level("tr", %{} = row), do: row
  defp kit_level(level, _row), do: level

  defp collapse(levels, nil), do: levels

  defp collapse(levels, table) do
    case Enum.split_while(levels, &(&1 not in @sections and &1 != "table")) do
      {inner, [_section_or_table | _rest]} -> inner ++ [table]
      {inner, []} -> inner
    end
  end

  # The palette entry whose markup opens with, and holds its content in, what `wanted?` asks for —
  # one of the arriving part's own kit first.
  defp holder(components, prefix, wanted?) do
    holders =
      Enum.filter(components, fn entry ->
        node = component_node(entry)
        opts = [components: [entry]]

        node != nil and
          wanted?.({Containment.element(node, opts), Containment.content_element(node, opts)})
      end)

    Enum.find(holders, &(kit_prefix(&1.name) == prefix)) || List.first(holders)
  end

  defp component_node(%{name: name}) when is_binary(name),
    do: Node.new(:component, tag: ".component", attrs: [{"component_name", {:string, name}}])

  defp component_node(_entry), do: nil

  defp kit_prefix(name) when is_binary(name), do: name |> String.split("-") |> hd()
  defp kit_prefix(_name), do: nil

  defp wrapped(template, levels, site, session),
    do: Enum.reduce(levels, template, &around(&1, &2, site, session))

  defp around(tag, inner, _site, _session) when is_binary(tag),
    do: "<#{tag}>" <> inner <> "</#{tag}>"

  # In the arriving part's own scope: its row and table are the same kit's.
  defp around(%{name: name} = entry, inner, site, session) do
    seeded = PaletteEntry.seeded(entry, [], :blank, Map.get(session, :components, []))

    ~s(<.component component_name="#{name}" site="#{site}"#{seeded}>) <> inner <> "</.component>"
  end

  defp site(%Node{} = head) do
    case Node.attr_text(head, "site") do
      site when is_binary(site) and site != "" -> site
      _unscoped -> "Global"
    end
  end
end
