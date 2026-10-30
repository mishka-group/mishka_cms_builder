# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.UiKit.HeadlessFurnishedTest do
  @moduledoc """
  Chelekom's headless table and tree, dropped and then edited the way an author edits them.

  The drop itself rendered: the table arrives with no rows and the tree with the outline its kit
  furnishes. What did not survive was the first ordinary edit afterwards:

    * a row added to the table, which raised `BadFunctionError`, because the palette had minted
      `row_id` — a function of the row — a random string for ending in `_id`;
    * a node added to the tree with the Inspector's Add, which copied the first node's keys as the
      empty string, so the new node carried `children: ""` and the tree, which iterates a node's
      children, raised.

  The components are a copy of the kit's own rows (`test/fixtures/chelekom_headless_furnished.json`,
  mishka_chelekom 51c329c2), installed for this module, and rendered through
  `LiveViewCompiler.render_template/2`, the published page's path.
  """
  use MishkaCmsCore.DataCase, async: false

  alias MishkaCmsBuilder.Collection
  alias MishkaCmsBuilder.PaletteEntry
  alias MishkaCmsCore.Runtime.Authoring.Tree
  alias MishkaCmsCore.Runtime.Authoring.Tree.Serializer
  alias MishkaCmsCore.Runtime.Compilers.Helpers, as: CompilerHelpers
  alias MishkaCmsCore.Runtime.Compilers.LiveViewCompiler
  alias MishkaCmsCore.Runtime.Handlers.UiKitHandler
  alias MishkaCmsCore.Runtime.States.CompileFailureState

  @moduletag timeout: 300_000

  @bundle Path.expand("../../fixtures/chelekom_headless_furnished.json", __DIR__)

  setup_all do
    context = module_sandbox()
    {:ok, _installed} = UiKitHandler.install_kit!(@bundle, site_id: nil)
    context
  end

  defp entry(name) do
    row =
      @bundle
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("components")
      |> Enum.find(&(&1["name"] == name))

    "Component"
    |> then(&CompilerHelpers.module_name(name, "Global", &1))
    |> CompileFailureState.clear()

    # The palette's own shape, a plain map as the core builds it: through `PaletteEntry.new!/1` the
    # furnishing's keys are made atoms and the outline it furnishes is not read.
    %{
      key: name,
      name: name,
      type: row["type"],
      template: row["template"],
      attrs: row["attrs"],
      slots: row["slots"],
      reads: PaletteEntry.reads(row),
      furnishing: row["extra"]["furnishing"],
      global?: true
    }
  end

  # The placed component's markup with one attribute replaced, which is what an Inspector edit is.
  defp edited(markup, name, change) do
    tree = Tree.parse!(markup)
    node = tree |> Tree.walk() |> Enum.find(&(&1.kind == :component))

    {:ok, source} = Collection.update(node, name, [], change)
    {:ok, tree} = Tree.set_attr(tree, node.id, name, {:expr, source})

    Serializer.serialize(tree)
  end

  defp rendered(markup) do
    case LiveViewCompiler.render_template(markup, %{}) do
      {:error, message} -> flunk("it raised: #{String.slice(message, 0, 400)}\n#{markup}")
      html -> html
    end
  end

  test "a dropped table renders the row the author adds" do
    markup =
      "chelekom-headless-table"
      |> entry()
      |> PaletteEntry.template("Global")
      |> edited("rows", &Collection.add(&1, %{name: "Ada Lovelace", role: "Engineer"}))

    html = rendered(markup)

    refute html =~ "Component failed to render!", markup
    assert html =~ "chelekom-table__row"
  end

  # The outline as it was furnished before mishka_chelekom 51c329c2 moved a leaf to the front: the
  # first node, the one Add copies, has children.
  test "a dropped tree renders the node the author adds beside one with children" do
    placed = "chelekom-headless-tree" |> entry() |> PaletteEntry.template("Global")
    node = placed |> Tree.parse!() |> Tree.walk() |> Enum.find(&(&1.kind == :component))
    {:ok, [overview | rest]} = Collection.read(node, "nodes")

    markup =
      placed
      |> edited("nodes", fn _furnished -> rest ++ [overview] end)
      |> edited("nodes", &Collection.add_blank(&1, []))
      |> edited("nodes", &Collection.add_blank(&1, [0, "children"]))

    html = rendered(markup)

    refute html =~ "Component failed to render!", markup
    assert html =~ "Getting started"
    assert [%{children: [_, _, %{label: ""}]} | _] = nodes_of(markup)
    assert %{children: []} = List.last(nodes_of(markup))
  end

  defp nodes_of(markup) do
    {:ok, nodes} =
      markup
      |> Tree.parse!()
      |> Tree.walk()
      |> Enum.find(&(&1.kind == :component))
      |> Collection.read("nodes")

    nodes
  end
end
