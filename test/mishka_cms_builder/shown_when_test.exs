# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.ShownWhenTest do
  @moduledoc """
  Which properties a component draws only while one of its switches is on, read off its markup.

  `chelekom-pagination` draws its first and last buttons under `:if={@rest[:show_edges]}`, so the
  palette sweep typed into `first_label` and `first_label_class` and saw nothing change.
  """
  use ExUnit.Case, async: true

  alias MishkaCmsBuilder.ShownWhen
  alias MishkaCmsCore.Runtime.Authoring.Tree

  @moduletag :unit

  defp attr(name, type, opts \\ %{}), do: %{"name" => name, "type" => type, "opts" => opts}

  test "the styled kit's pagination: its first and last buttons wait for Show edges" do
    row =
      MishkaCmsCore.Runtime.Handlers.UiKitHandler.default_bundle_path()
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("components")
      |> Enum.find(&(&1["name"] == "chelekom-pagination"))

    switches = ShownWhen.switches(row)

    for name <- ~w(first_label first_label_class last_label last_label_class) do
      assert switches[name] == "show_edges", "#{name} is not behind Show edges"
    end

    refute Map.has_key?(switches, "next_label")
    refute Map.has_key?(switches, "previous_label")
  end

  test "a property read anywhere outside the switch shows without it" do
    entry = %{
      template:
        ~S|<b :if={@open}>{@caption}</b><a :if={@open} title={@hint}></a><i title={@hint}></i>|,
      attrs: [attr("open", "boolean", %{"default" => false}), attr("hint", "string")]
    }

    assert ShownWhen.switches(entry) == %{}
  end

  test "a switch guards what its element's children read too" do
    entry = %{
      template: ~S|<div :if={@open}><span class={@inner_class}></span></div>|,
      attrs: [attr("open", "boolean", %{"default" => false}), attr("inner_class", "string")]
    }

    assert ShownWhen.switches(entry) == %{"inner_class" => "open"}
  end

  # `:if={@label}` guards a label's class, but `label` is words: "shows only when Label is on" is not
  # true of it.
  test "a condition on words is not a switch" do
    entry = %{
      template: ~S|<span :if={@label} class={@label_class}>{@label}</span>|,
      attrs: [attr("label", "string"), attr("label_class", "string")]
    }

    assert ShownWhen.switches(entry) == %{}
  end

  test "and a list read in a :for is read before the :if is asked" do
    entry = %{
      template: ~S|<li :for={item <- @items} :if={@open}>{item}</li>|,
      attrs: [attr("open", "boolean", %{"default" => false}), attr("items", "list")]
    }

    assert ShownWhen.switches(entry) == %{}
  end

  test "a switch is on when written, or declared on and left alone" do
    entry = %{attrs: [attr("visible", "boolean", %{"default" => true})]}
    {:ok, tree} = Tree.parse(~S|<.component component_name="x" show_edges />|)
    node = tree |> Tree.walk() |> hd()

    assert ShownWhen.on?(node, "show_edges", entry)
    assert ShownWhen.on?(node, "visible", entry)
    refute ShownWhen.on?(node, "grouped", entry)
  end
end
