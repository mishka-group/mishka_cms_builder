# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.ShownWhen do
  @moduledoc """
  The properties a component draws only while one of its switches is on.

  ## Why the Inspector has to say so

  `chelekom-pagination` draws its first and last buttons under `:if={@rest[:show_edges]}`, so
  `first_label`, `first_label_class`, `last_label` and `last_label_class` reach the canvas only once
  Show edges is on. Until then, whatever is typed into them changes nothing, and the palette sweep
  reported exactly that. The fields work; they are waiting for a switch the panel offers a few rows
  away, and the panel says which.

  ## Read off the component's markup

  A property is behind a switch when EVERY place the component reads it sits inside an element whose
  `:if` is that switch alone — `:if={@rest[:show_edges]}` or `:if={@show_edges}` — itself or through
  an ancestor. One read anywhere else (outside such an element, in a `:for`, in a helper's body, in
  text) and the property may show without it, so nothing is said. A switch counts only when the panel
  offers it as one: a boolean the component declares, or a `@rest` key its body reads as a flag
  (`MishkaCmsCore.Runtime.Authoring.Inspector.rest_attrs/1`).
  """

  alias MishkaCmsCore.Runtime.Authoring.Inspector
  alias MishkaCmsCore.Runtime.Authoring.Tree
  alias MishkaCmsCore.Runtime.Authoring.Tree.Node

  @doc """
  Each property drawn only behind a switch, with that switch's name: `%{"first_label" =>
  "show_edges"}`. Empty for a component with no markup, or none behind a switch.
  """
  @spec switches(map()) :: %{String.t() => String.t()}
  def switches(entry) do
    template = Inspector.template(entry)
    offered = entry |> offered() |> MapSet.intersection(conditions(template))

    with false <- MapSet.size(offered) == 0,
         {:ok, tree} <- Tree.parse(template) do
      gated = tree |> Tree.children(:root) |> Enum.flat_map(&reads(tree, &1, []))
      source = Enum.join([template | Enum.map(Inspector.helpers(entry), &code/1)], "\n")

      for name <- declared(entry),
          switch = behind(name, gated, source),
          switch in offered,
          into: %{},
          do: {name, switch}
    else
      _no_switch -> %{}
    end
  end

  # The names a condition in the markup is nothing but, read before anything is parsed: most
  # components have none that is a switch, and parsing every one of them would cost the palette's
  # open half a second.
  defp conditions(template) do
    ~r/:if=\{\s*@(?:rest\[:)?([a-z_][a-zA-Z0-9_]*)\]?\s*\}/
    |> Regex.scan(template, capture: :all_but_first)
    |> List.flatten()
    |> MapSet.new()
  end

  @doc """
  Whether the switch `name` is on for this node: written, and not written `false` or `nil`, or not
  written at all and declared on by default — `chelekom-skeleton`'s `visible`.
  """
  @spec on?(Node.t(), String.t(), map()) :: boolean()
  def on?(node, name, entry) do
    case Node.attr(node, name) do
      nil -> declared_on?(entry, name)
      written -> written not in [{:expr, "false"}, {:expr, "nil"}]
    end
  end

  defp declared_on?(entry, name) do
    case Enum.find(Inspector.attrs(entry), &(Inspector.name(&1) == name)) do
      nil -> false
      attr -> Inspector.default(attr) == true
    end
  end

  # Every assign read in an attribute of `node` and below it, with the switches that guard the read.
  defp reads(tree, %Node{} = node, inherited) do
    own = node |> Node.attr(":if") |> switch_of()
    guarded = (own && [own | inherited]) || inherited

    here =
      for {name, {:expr, source}} <- node.attrs,
          name != ":if",
          read <- assigns_in(source),
          do: {read, (name == ":for" && inherited) || guarded}

    here ++ Enum.flat_map(Tree.children(tree, node.id), &reads(tree, &1, guarded))
  end

  defp reads(_tree, _node, _inherited), do: []

  # The one switch a condition is, or `nil` for anything else.
  defp switch_of({:expr, source}) do
    case Code.string_to_quoted(String.trim(source)) do
      {:ok, {{:., _, [Access, :get]}, _, [{:@, _, [{:rest, _, context}]}, key]}}
      when is_atom(context) and is_atom(key) ->
        Atom.to_string(key)

      {:ok, {:@, _, [{name, _, context}]}} when is_atom(name) and is_atom(context) ->
        Atom.to_string(name)

      _other ->
        nil
    end
  end

  defp switch_of(_condition), do: nil

  defp assigns_in(source) do
    ~r/@([a-z_][a-zA-Z0-9_]*)/
    |> Regex.scan(source, capture: :all_but_first)
    |> List.flatten()
  end

  # The switch guarding every read of `name`, when the reads in guarded attributes are all of them.
  defp behind(name, gated, source) do
    guards = for {^name, switches} <- gated, do: switches
    total = ~r/@#{name}(?![a-zA-Z0-9_])/ |> Regex.scan(source) |> length()

    with true <- guards != [] and length(guards) == total,
         [switch | _] <- guards |> Enum.reduce(&common/2) |> Enum.sort() do
      switch
    else
      _shown_without_one -> nil
    end
  end

  defp common(switches, held), do: Enum.filter(held, &(&1 in switches))

  defp declared(entry) do
    for attr <- Inspector.attrs(entry),
        Inspector.type(attr) != "global",
        name = Inspector.name(attr),
        is_binary(name),
        do: name
  end

  # A SWITCH IS ON OR OFF. `:if={@label}` guards a label's class too, but `label` is words, and
  # "shows only when Label is on" would not be true of it.
  defp offered(entry) do
    for attr <- Inspector.attrs(entry) ++ Inspector.rest_attrs(entry),
        Inspector.value_type(attr) == "boolean",
        into: MapSet.new(),
        do: Inspector.name(attr)
  end

  defp code(helper) do
    case helper do
      %{"code" => code} when is_binary(code) -> code
      %{code: code} when is_binary(code) -> code
      _other -> ""
    end
  end
end
