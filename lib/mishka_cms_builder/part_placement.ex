# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.PartPlacement do
  @moduledoc """
  Puts a kit's part in the component it belongs to, when it arrives where none of those holds it.

  A kit ships some components that are pieces of another one: Chelekom's Card Title, Card Media,
  Card Content and Card Footer are sections of a Card, its Dropdown Trigger and Dropdown Content
  the two halves of a Dropdown. Each renders on its own — it is a `<div>` — but the look is the
  parent's, and a Card Footer dropped on a navbar landed in the navbar's `:end_content` slot as a
  padded box nobody asked for. The drop that `MishkaCmsBuilder.TablePlacement` answers for a table
  cell is the same gesture here: the part arrives inside a new parent, as one insert and one undo
  step, and the author is told so. Inside its parent, at any depth, it lands as it is.

  ## What a part is

  Read off the kit, never off the name. A component is a part of another when every example the kit
  ships for it opens with that other component — the kit only ever shows it inside one — and the
  two are one family in the kit's own catalogue (`extra.component`, `"card"` for all five Card
  pieces). Both are needed: Chelekom shows its number field under a heading every time, and the
  heading is not its home. A kit that names no families has no parts, and nothing changes for it.

  The palette carries both facts, answered in its own query (`with_kit_facts/1`, `kit_facts/1`),
  so a placement asks nothing of the database.

  Only a part that is a plain box. One whose markup opens with an element HTML gives a home of its
  own — a table row, a list item, a definition term, a word of phrasing — is answered by
  `MishkaCmsCore.Runtime.Authoring.Containment` and `TablePlacement`, whose rules already say where
  it may go; a second parent put around it here would land where HTML refuses it.

  ## Moves are not wrapped

  A part already on the page that is dragged out of its parent is moved like any other node, because
  nothing about it breaks the page. Wrapping is for a part arriving — from the palette, a snippet, a
  paste. A component's own markup is a fragment placed elsewhere later, so a part at its top level
  is left as it is too.
  """

  use Gettext, backend: MishkaCmsCore.Gettext

  require Ash.Expr

  alias MishkaCmsBuilder.PaletteEntry
  alias MishkaCmsBuilder.Placement
  alias MishkaCmsBuilder.TablePlacement
  alias MishkaCmsCore.Runtime.Authoring.Containment
  alias MishkaCmsCore.Runtime.Authoring.Tree
  alias MishkaCmsCore.Runtime.Authoring.Tree.Node

  @typedoc "Whether a placement put a part's parent around it, and the two names the author is told."
  @type outcome :: :none | {:held, String.t(), String.t()}

  # The elements a part may open with: a box, or a component call the containment rules cannot read.
  @boxes [nil, "div"]

  @doc "What the author is told after a placement, or `nil` when there is nothing to say."
  @spec told(outcome() | term()) :: String.t() | nil
  def told({:held, part, holder}),
    do:
      gettext("%{part} goes inside %{holder}, so it arrived in a new one.",
        part: part,
        holder: holder
      )

  def told(_outcome), do: nil

  @doc """
  The template to insert at `parent` (a node id, `"root"` or `:root`), and whether a parent was put
  around it.

  Untouched when its first element is not a kit's part, or when `parent` or an element around it is
  already that part's parent.
  """
  @spec wrap(String.t(), map(), String.t() | :root | nil) :: {String.t(), outcome()}
  def wrap(template, session, parent) do
    components = Map.get(session, :components, [])

    with false <- TablePlacement.fragment?(session),
         {:ok, tree} <- Tree.parse(template),
         %Node{kind: :component} = head <- Placement.head(tree),
         name when is_binary(name) <- Node.component_name(head),
         %{name: holder} = entry <- holder(name, components),
         true <- Containment.element(head, components: components) in @boxes,
         false <- held?(Map.get(session, :tree), parent, holder) do
      {around(entry, template, site(head), components), {:held, named(name), named(holder)}}
    else
      _at_home -> {template, :none}
    end
  end

  @doc """
  The palette entry of the component `name` belongs inside, or `nil` when it is not a kit's part —
  see the moduledoc. Both have to be in `components`, the palette.
  """
  @spec holder(String.t(), [map()]) :: map() | nil
  def holder(name, components) do
    with %{} = part <- entry(components, name),
         family when is_binary(family) <- Map.get(part, :kit_family),
         [holder | _rest] = heads when is_binary(holder) and holder != name <-
           Map.get(part, :example_heads) || [],
         true <- Enum.all?(heads, &(&1 == holder)),
         %{kit_family: ^family} = parent <- entry(components, holder) do
      parent
    else
      _not_a_part -> nil
    end
  end

  @doc """
  Answers in Postgres what `holder/2` asks of every row the palette reads: the component's family in
  its kit's catalogue, and the component each of the kit's examples for it opens with.

  Calculations, because `extra` is the column the palette must not pull whole — a component its kit
  documents at length carries hundreds of kilobytes of examples, and these are a few short strings.
  """
  @spec with_kit_facts(Ash.Query.t()) :: Ash.Query.t()
  def with_kit_facts(query) do
    query
    |> Ash.Query.calculate(
      :kit_family,
      :string,
      Ash.Expr.expr(fragment("?->>'component'", extra))
    )
    |> Ash.Query.calculate(
      :example_heads,
      {:array, :string},
      Ash.Expr.expr(
        fragment(
          "ARRAY(SELECT substring(example->>'source' from 'component_name=\"([^\"]+)\"') FROM jsonb_array_elements(CASE WHEN jsonb_typeof(?->'examples') = 'array' THEN ?->'examples' ELSE '[]'::jsonb END) AS example)",
          extra,
          extra
        )
      )
    )
  end

  @doc "The facts `with_kit_facts/1` read for one row, as the palette entry carries them."
  @spec kit_facts(map()) :: %{kit_family: String.t() | nil, example_heads: [String.t() | nil]}
  def kit_facts(%{calculations: %{} = facts}),
    do: %{kit_family: facts[:kit_family], example_heads: facts[:example_heads] || []}

  def kit_facts(_row), do: %{kit_family: nil, example_heads: []}

  defp entry(components, name), do: Enum.find(components, &(Map.get(&1, :name) == name))

  # Whether `parent`, or an element around it, is already the part's parent.
  defp held?(%Tree{} = tree, parent, holder) when is_binary(parent) and parent != "root" do
    tree
    |> Tree.path(parent)
    |> Enum.any?(&(Node.component_name(&1) == holder))
  end

  defp held?(_tree, _parent, _holder), do: false

  # In the arriving part's own scope, as `TablePlacement` builds a kit's table around its cell.
  defp around(%{name: name} = entry, inner, site, components) do
    seeded = PaletteEntry.seeded(entry, [], :blank, components)

    ~s(<.component component_name="#{name}" site="#{site}"#{seeded}>) <> inner <> "</.component>"
  end

  defp site(%Node{} = head) do
    case Node.attr_text(head, "site") do
      site when is_binary(site) and site != "" -> site
      _unscoped -> "Global"
    end
  end

  # What the author reads: the words after the kit's name, which the two share — "Card Footer",
  # "Card".
  defp named(name) do
    words =
      case String.split(name, "-") do
        [_kit | [_ | _] = words] -> words
        words -> words
      end

    Enum.map_join(words, " ", &String.capitalize/1)
  end
end
