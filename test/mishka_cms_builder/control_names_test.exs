# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.ControlNamesTest do
  @moduledoc """
  Two independent drops must not post under, or group by, one form-control name.

  `chelekom-headless-segmented-control` arrives furnished as `name="period"`. Its segments are radio
  buttons, and the browser groups radio buttons by name, so two dropped controls were one group:
  choosing in the second cleared the first, and only one of them ever showed a selection.
  """
  use ExUnit.Case, async: true

  alias MishkaCmsBuilder.ControlNames
  alias MishkaCmsCore.Runtime.Authoring.Tree
  alias MishkaCmsCore.Runtime.Authoring.Tree.Node

  @moduletag :unit

  # A copy of the kit's own row, from mishka_chelekom 51c329c2.
  @segmented "../fixtures/chelekom_headless_furnished.json"
             |> Path.expand(__DIR__)
             |> File.read!()
             |> Jason.decode!()
             |> Map.fetch!("components")
             |> Enum.find(&(&1["name"] == "chelekom-headless-segmented-control"))
             |> then(&%{name: &1["name"], attrs: &1["attrs"], template: &1["template"]})

  @icon %{
    name: "chelekom-icon",
    attrs: [%{"name" => "name", "type" => "string", "opts" => %{"required" => true}}],
    template: ~S|<span class={[@name]}></span>|
  }

  # A field by its markup: its control's name and value both come from what it declares.
  @radio %{
    name: "kit-radio",
    attrs: [
      %{"name" => "name", "type" => "string", "opts" => %{}},
      %{"name" => "value", "type" => "string", "opts" => %{}}
    ],
    template: ~S|<input type="radio" name={@name} value={@value} />|
  }

  @palette [@segmented, @icon, @radio]

  defp segmented(name \\ "period"),
    do:
      ~s(<.component component_name="chelekom-headless-segmented-control" site="Global" name="#{name}" options={["Day", "Week"]} />)

  defp tree!(source) do
    {:ok, tree} = Tree.parse(source)
    tree
  end

  # Placed again: the arrival's node ids are new, its markup's names carried in verbatim.
  defp place(tree, source, parent \\ :root) do
    added = tree!(source)
    index = length(Tree.children(tree, parent))
    {:ok, merged} = Tree.insert(tree, added, parent, index)
    ControlNames.dedupe(merged, Map.keys(added.nodes), @palette)
  end

  defp names(tree, component) do
    for node <- Tree.walk(tree),
        Node.component_name(node) == component,
        do: Node.attr_text(node, "name")
  end

  test "a second dropped control is renamed, the one already placed is left alone" do
    tree = segmented() |> tree!() |> place(segmented())

    assert names(tree, "chelekom-headless-segmented-control") == ["period", "period_2"]
  end

  test "a third takes the next free number, and a gap is filled first" do
    tree = segmented() |> tree!() |> place(segmented()) |> place(segmented())

    assert names(tree, "chelekom-headless-segmented-control") == [
             "period",
             "period_2",
             "period_3"
           ]

    tree = (segmented() <> segmented("period_3")) |> tree!() |> place(segmented())

    assert names(tree, "chelekom-headless-segmented-control") == [
             "period",
             "period_3",
             "period_2"
           ]
  end

  # The browser groups radio buttons per form, and a submission collects its keys per form.
  test "the same name in another form is another name" do
    forms =
      ~s(<form id="one" phx-submit="one">#{segmented()}</form><form id="two" phx-submit="two"></form>)

    tree = tree!(forms)
    two = Enum.find(Tree.walk(tree), &(Node.attr_text(&1, "id") == "two"))

    assert tree
           |> place(segmented(), two.id)
           |> names("chelekom-headless-segmented-control") == ["period", "period"]
  end

  test "a raw control already answering to the name counts" do
    tree = ~s(<input type="radio" name="period" value="a" />) |> tree!() |> place(segmented())

    assert names(tree, "chelekom-headless-segmented-control") == ["period_2"]
  end

  # One example with a group in it is one group, on purpose.
  test "arrivals that share a name keep sharing it, renamed together" do
    pair = ~s(<div>#{segmented()}#{segmented()}</div>)

    assert "" |> tree!() |> place(pair) |> names("chelekom-headless-segmented-control") == [
             "period",
             "period"
           ]

    tree = segmented() |> tree!() |> place(pair)

    assert names(tree, "chelekom-headless-segmented-control") == [
             "period",
             "period_2",
             "period_2"
           ]
  end

  describe "what it leaves alone" do
    test "an icon's name, which is no control's" do
      icon = ~s(<.component component_name="chelekom-icon" site="Global" name="hero-star" />)

      assert icon |> tree!() |> place(icon) |> names("chelekom-icon") == [
               "hero-star",
               "hero-star"
             ]
    end

    # FormPlacement binds a field to the form it joins; its name is that form's business.
    test "a component the kit calls a field" do
      radio = ~s(<.component component_name="kit-radio" site="Global" name="plan" value="a" />)

      assert radio |> tree!() |> place(radio) |> names("kit-radio") == ["plan", "plan"]
    end

    test "a name bound to a form field" do
      bound =
        ~s(<.component component_name="chelekom-headless-segmented-control" site="Global" name={f[:period].name} options={[]} />)

      tree = bound |> tree!() |> place(bound)

      assert names(tree, "chelekom-headless-segmented-control") == [
               "f[:period].name",
               "f[:period].name"
             ]
    end

    test "a raw control the author dropped, which may be joining a group on purpose" do
      radio = ~s(<input type="radio" name="period" value="a" />)

      tree = radio |> tree!() |> place(radio)

      assert for(node <- Tree.walk(tree), do: Node.attr_text(node, "name")) == [
               "period",
               "period"
             ]
    end
  end

  test "a name that ends in a list or a key keeps its brackets last" do
    tags =
      &~s(<.component component_name="chelekom-headless-segmented-control" site="Global" name="#{&1}" options={[]} />)

    tree = tags.("tags[]") |> tree!() |> place(tags.("tags[]"))
    assert names(tree, "chelekom-headless-segmented-control") == ["tags[]", "tags_2[]"]

    tree = tags.("user[plan]") |> tree!() |> place(tags.("user[plan]"))
    assert names(tree, "chelekom-headless-segmented-control") == ["user[plan]", "user[plan_2]"]
  end
end
