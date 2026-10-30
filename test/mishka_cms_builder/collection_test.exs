# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.CollectionTest do
  @moduledoc """
  An attribute that holds a list, edited as a list.

  `chelekom-filterable-gallery` keeps its whole content in two `list` attributes — the filter
  buttons and the pictures behind them — and thirty-nine attributes across the shipped kit are
  shaped the same way. Every one of them drew a one-line text box, and what that box wrote was a
  STRING: a component that maps over its own attribute raised the moment anything was typed. The
  report reads "we cannot add any image and it's not clear how it works".

  What is pinned here is the round trip. The panel reads the list out of the document, changes one
  item, and writes the whole thing back as source the editor can read again — and an attribute that
  is not data is refused rather than overwritten with whatever could be made of it.
  """
  use ExUnit.Case, async: true

  alias MishkaCmsBuilder.Collection
  alias MishkaCmsCore.Runtime.Authoring.Inspector
  alias MishkaCmsCore.Runtime.Authoring.Tree

  @moduletag :unit

  defp parsed(markup) do
    {:ok, tree} = Tree.parse(markup)
    tree |> Tree.walk() |> Enum.find(&(&1.kind == :component))
  end

  describe "reading what is there" do
    test "a list written as an expression" do
      node = parsed(~S|<.component component_name="x" filters={["One", "Two"]} />|)

      assert Collection.read(node, "filters") == {:ok, ["One", "Two"]}
    end

    test "a list of maps, keys and all" do
      node = parsed(~S|<.component component_name="x" media={[%{src: "/a.jpg", alt: "A"}]} />|)

      assert Collection.read(node, "media") == {:ok, [%{src: "/a.jpg", alt: "A"}]}
    end

    test "an attribute that is not there falls back to the declared default" do
      node = parsed(~S|<.component component_name="x" />|)

      assert Collection.read(node, "filters", ["All"]) == {:ok, ["All"]}
      assert Collection.read(node, "filters") == {:ok, []}
    end

    # THE ONE ANSWER THAT IS NOT A LIST. `media={@photos}` is an author binding the attribute to
    # something outside the page, and the panel must leave it exactly as written — reading it as an
    # empty list and writing that back would delete their work on the next click.
    test "an attribute bound to something outside the page is refused" do
      node = parsed(~S|<.component component_name="x" media={@photos} />|)

      assert Collection.read(node, "media") == :error
    end

    test "and so is a call, however list-shaped it looks" do
      node = parsed(~S|<.component component_name="x" media={Enum.map(@p, & &1)} />|)

      assert Collection.read(node, "media") == :error
    end
  end

  describe "changing one item" do
    test "adds at the end, removes by index, and replaces in place" do
      assert Collection.add(["a"], "b") == ["a", "b"]
      assert Collection.remove(["a", "b", "c"], 1) == ["a", "c"]
      assert Collection.put(["a", "b"], 1, "B") == ["a", "B"]
      assert Collection.put_in_item([%{src: "x"}], 0, :src, "y") == [%{src: "y"}]
    end

    # A STALE CLICK MUST NOT TAKE THE EDITOR DOWN. The panel and the document disagree for one render
    # after an undo, and a button pressed in that window addresses an item that is no longer there.
    test "a field named by the text the browser sent is found among the item's own" do
      assert Collection.put_in_item([%{src: "x"}], 0, "src", "y") == [%{src: "y"}]
      assert Collection.put_in_item([%{"src" => "x"}], 0, "src", "y") == [%{"src" => "y"}]
    end

    test "a field the item does not have changes nothing, and no atom is made of its name" do
      name = "field_nobody_declared_#{System.unique_integer([:positive])}"

      assert Collection.put_in_item([%{src: "x"}], 0, name, "y") == [%{src: "x"}]
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end

    test "an index past the end changes nothing" do
      assert Collection.put(["a"], 4, "b") == ["a"]
      assert Collection.put_in_item(["a"], 4, :src, "b") == ["a"]
      assert Collection.remove(["a"], 4) == ["a"]
      assert Collection.put_in_item(["a"], 0, :src, "b") == ["a"]
    end
  end

  # A MAP IS READ OUT AS ITS PAIRS. `chelekom-flash` holds `%{"info" => "…"}` and
  # `chelekom-pagination` a map of query parameters, and a pair is edited as a pair — one field for
  # each side. Reading one as a single value put a tuple through `to_string/1`, which raised out of
  # LiveView's own diff and took the editor down the moment such a component was selected.
  describe "a map attribute" do
    test "is read as pairs" do
      node = parsed(~S|<.component component_name="x" params={%{"kind" => "banner"}} />|)

      assert Collection.read(node, "params") == {:ok, [{"kind", "banner"}]}
      assert Collection.pair?({"kind", "banner"})
      refute Collection.pair?("kind")
    end

    test "and one side changes without disturbing the other" do
      items = [{"kind", "banner"}, {"size", "large"}]

      assert Collection.put_side(items, 0, :value, "toast") == [
               {"kind", "toast"},
               {"size", "large"}
             ]

      assert Collection.put_side(items, 1, :key, "scale") == [
               {"kind", "banner"},
               {"scale", "large"}
             ]

      assert Collection.put_side(items, 9, :key, "x") == items
      assert Collection.put_side(["plain"], 0, :key, "x") == ["plain"]
    end

    test "and a new row is an empty pair" do
      assert Collection.blank([{"kind", "banner"}]) == {"", ""}
    end

    # Its pairs are what the panel edits, and a map is what goes back: written as the list of pairs it
    # was edited as, `Phoenix.Flash.get(@flash, :info)` read a list.
    test "and is written back a map" do
      node = parsed(~S|<.component component_name="x" params={%{"kind" => "banner"}} />|)

      assert {:ok, source} =
               Collection.update(
                 node,
                 "params",
                 %{},
                 &Collection.put_side(&1, 0, :value, "toast")
               )

      assert {%{"kind" => "toast"}, _bindings} = Code.eval_string(source)
    end
  end

  describe "the row a new one starts as" do
    test "carries the same fields its neighbours do, blank" do
      assert Collection.blank([%{src: "/a.jpg", alt: "A"}]) == %{src: "", alt: ""}
    end

    test "and is a plain value when there is nothing to copy" do
      assert Collection.blank(["One", "Two"]) == ""
      assert Collection.blank([]) == ""
    end

    # THE REPORTED DEFECT. A tree's node holds its own `children`, and Add copied the first node's
    # keys as the empty string, so a node added beside one with children carried `children: ""` and
    # the tree, which iterates a node's children, raised on the canvas.
    test "keeps a list a list and a map a map" do
      nodes = [
        %{
          label: "Getting started",
          value: "start",
          children: [%{label: "Install"}],
          meta: %{a: 1}
        }
      ]

      assert Collection.blank(nodes) == %{label: "", value: "", children: [], meta: %{}}
    end

    test "and a switch off" do
      assert Collection.blank([%{label: "Day", disabled: true}]) == %{label: "", disabled: false}
    end

    # `chelekom-headless-segmented-control` takes `{label, value, disabled}` as well as pairs.
    test "a tuple of any size is blank in each of its places" do
      assert Collection.blank(["Day", {"Week", "week", true}]) == {"", "", false}
    end
  end

  # A TREE IS A LIST OF NODES THAT HOLD LISTS OF NODES. The panel edits each level in place, and a
  # path says which list a change is for: the item's index, then the field holding the next list.
  describe "a collection inside an item" do
    @tree [
      %{label: "Overview", value: "overview"},
      %{
        label: "Getting started",
        value: "start",
        children: [%{label: "Installation", value: "install"}]
      }
    ]

    test "one field of a nested item changes and every level around it stays as it was" do
      changed =
        Collection.within(
          @tree,
          [1, "children"],
          &Collection.put_in_item(&1, 0, "label", "Setup")
        )

      assert [_overview, %{children: [%{label: "Setup", value: "install"}]}] = changed
      assert hd(changed) == hd(@tree)
    end

    test "an item added to a nested list takes the shape of its siblings" do
      changed = Collection.add_blank(@tree, [1, "children"])

      assert [_overview, %{children: [_install, %{label: "", value: ""}]}] = changed
    end

    test "and to an empty one, the shape of the same list elsewhere in the tree" do
      tree = List.replace_at(@tree, 0, %{label: "Overview", value: "overview", children: []})

      assert [%{children: [%{label: "", value: ""}]}, _start] =
               Collection.add_blank(tree, [0, "children"])
    end

    test "an item added at the top keeps a list-valued key a list" do
      assert [_one, _two, %{label: "", value: "", children: []}] =
               Collection.add_blank(Enum.reverse(@tree), [])
    end

    test "a map inside an item is edited as its pairs and stays a map" do
      items = [%{label: "A", params: %{"page" => "1"}}]

      changed = Collection.within(items, [0, "params"], &Collection.put_side(&1, 0, :value, "2"))

      assert changed == [%{label: "A", params: %{"page" => "2"}}]
    end

    test "a path that no longer leads anywhere changes nothing" do
      fun = &Collection.put_in_item(&1, 0, "label", "x")

      assert Collection.within(@tree, [9, "children"], fun) == @tree
      assert Collection.within(@tree, [0, "children"], fun) == @tree
      assert Collection.within(@tree, [1, "label"], fun) == @tree
      assert Collection.within(@tree, ["1", "children"], fun) == @tree
    end
  end

  # WHAT THE BOX SENDS IS TEXT; WHAT THE FIELD HOLDS MAY NOT BE. Writing the text as it came is
  # what turned a node's `children` into a string, so a write is read as the kind of value it replaces,
  # and one that cannot be read that way is refused.
  describe "a typed write" do
    test "into a list or a map is refused, whoever sends it" do
      items = [%{label: "A", children: [%{label: "B"}], meta: %{a: 1}}]

      assert Collection.put_in_item(items, 0, "children", "[]") == items
      assert Collection.put_in_item(items, 0, "meta", "%{}") == items
      assert Collection.put([["a"]], 0, "a") == [["a"]]
    end

    test "into a switch is a switch" do
      assert Collection.put_in_item([%{disabled: false}], 0, "disabled", "true") == [
               %{disabled: true}
             ]

      assert Collection.put_element([{"Day", "day", true}], 0, 2, "false") == [
               {"Day", "day", false}
             ]
    end

    test "into a number is a number, or nothing" do
      assert Collection.put_in_item([%{size: 2}], 0, "size", "5") == [%{size: 5}]
      assert Collection.put_in_item([%{size: 2}], 0, "size", "five") == [%{size: 2}]
    end

    test "one place of a tuple changes and the others stay" do
      items = [{"Day", "day", true}, "Week"]

      assert Collection.put_element(items, 0, 0, "Today") == [{"Today", "day", true}, "Week"]
      assert Collection.put_element(items, 1, 0, "x") == items
      assert Collection.put_element(items, 0, 7, "x") == items
    end

    test "an atom is the component's own word and is not retyped" do
      assert Collection.put_in_item([%{type: :icon}], 0, "type", "text") == [%{type: :icon}]
    end
  end

  describe "writing it back" do
    test "is source the editor can read again" do
      items = [%{src: "/a.jpg", alt: "A", category: "Branding"}, %{src: "/b.jpg"}]
      written = Collection.write(items)

      node = parsed(~S|<.component component_name="x" media={| <> written <> ~S|} />|)

      assert Collection.read(node, "media") == {:ok, items}
    end

    # `inspect/1` shortens a long list with an ellipsis by default, and an ellipsis is not Elixir.
    test "and a long one is written whole" do
      items = Enum.map(1..200, &%{src: "/#{&1}.jpg"})

      node =
        parsed(~S|<.component component_name="x" media={| <> Collection.write(items) <> ~S|} />|)

      assert Collection.read(node, "media") == {:ok, items}
    end
  end

  describe "which attributes this is for" do
    @bundle MishkaCmsCore.Runtime.Handlers.UiKitHandler.default_bundle_path()

    test "every list, map and keyword list the kit declares" do
      components =
        @bundle |> File.read!() |> Jason.decode!() |> Map.fetch!("components")

      collections =
        for entry <- components,
            attr <- Inspector.attrs(entry),
            match?(
              {:collection, _kind},
              Inspector.widget(attr, Inspector.features(entry), entry)
            ),
            do: "#{entry["name"]}.#{Inspector.name(attr)}"

      assert length(collections) >= 30,
             "the kit is full of these and only #{length(collections)} were recognised"

      assert "chelekom-filterable-gallery.media" in collections
      assert "chelekom-filterable-gallery.filters" in collections
    end

    test "and nothing that holds one value" do
      text = %{"name" => "title", "type" => "string", "opts" => %{}}
      number = %{"name" => "total", "type" => "integer", "opts" => %{}}

      refute match?({:collection, _}, Inspector.widget(text))
      refute match?({:collection, _}, Inspector.widget(number))
    end
  end
end
