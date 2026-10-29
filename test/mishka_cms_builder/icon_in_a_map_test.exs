# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.IconInAMapTest do
  @moduledoc """
  A label is not always a word, and a count of zero is not a component.

  Dropping a `chelekom-pagination` gave an author a strip with no pages on it and two empty boxes
  where its arrows should be, and an Inspector with no way to change either. Three separate causes,
  none of them about colour, which is what it was reported as.

  ## The count

  Placement leaves a required STRING empty on purpose: the Inspector marks it Required and the save
  refuses until it is filled. A number has no empty — `blank_attr?/2` reads the text "0" as filled —
  so a numeric seed is a value nobody is ever told to replace, and zero is the one number that can
  render as nothing. `chelekom-pagination` builds `range(1, total)`, which for zero is the empty
  list.

  ## The arrows

  The canvas generates a CSS rule for every icon the document could draw, because the site's own
  stylesheet only carries the ones its pages already render. It looked for those names in
  `{:string, …}` attributes — and pagination's five arrows and its separator are declared as `map`,
  each defaulting to `%{type: :icon, value: "hero-chevron-left"}`, which the bundle carries as an
  `__atom_map__` envelope. No rule was generated, so each drew an empty box.

  ## And no way to change them

  Read as a plain map attribute, each of those six drew a text box with nothing an author could
  usefully type into it. The widget is decided from the DECLARED DEFAULT rather than from the
  attribute's name, so a kit that spells the same idea differently is covered without being named —
  and the control writes the map back, because a component reading `Map.get(@previous_label, :type)`
  off a binary raises.
  """
  use ExUnit.Case, async: true

  alias MishkaCmsBuilder.PaletteEntry

  @moduletag :unit

  @bundle MishkaCmsCore.Runtime.Handlers.UiKitHandler.default_bundle_path()

  setup_all do
    entries = @bundle |> File.read!() |> Jason.decode!() |> Map.fetch!("components")
    {:ok, entries: entries, by_name: Map.new(entries, &{&1["name"], &1})}
  end

  # `seeded/3` takes the palette's own entry shape, which is atom-keyed — the bundle's is the JSON
  # it was read from.
  defp placeable(entry) do
    %{
      name: entry["name"],
      template: entry["template"],
      attrs: entry["attrs"] || [],
      slots: entry["slots"] || []
    }
  end

  describe "a required number the author never filled in" do
    test "is dropped as something the component can draw", %{by_name: by_name} do
      placed = PaletteEntry.seeded(placeable(by_name["chelekom-pagination"]))

      assert placed =~ ~r/total=\{(\d+)\}/
      assert [_whole, total] = Regex.run(~r/total=\{(\d+)\}/, placed)
      assert String.to_integer(total) > 0, "a pagination of nothing pages renders no page"
    end

    # THE RULE, NOT THE ONE COMPONENT. Every required numeric in every installed kit.
    test "and so is every other required number in the kit", %{entries: entries} do
      zeroed =
        for entry <- entries,
            placed = PaletteEntry.seeded(placeable(entry)),
            [_whole, name] <- Regex.scan(~r/(\w+)=\{0\}/, placed),
            do: "#{entry["name"]}.#{name}"

      assert zeroed == [], "these are placed holding the one number that can render as nothing"
    end
  end
end
