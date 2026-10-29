# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.FieldsTest do
  @moduledoc """
  A previewed form field appears in a form; a dropped one does not.

  The detector fails OPEN — get it wrong and every field previews bare, exactly as before, with no
  error anywhere to notice. So the set it selects is pinned against the installed bundles rather than
  against a fixture, and the two components that sit one signal away from inclusion are named.
  """
  use ExUnit.Case, async: true

  alias MishkaCmsCore.Runtime.Authoring.Fields

  @moduletag :unit

  @kits_dir MishkaCmsCore.Runtime.Handlers.UiKitHandler.kits_dir()

  setup_all do
    components =
      @kits_dir
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        path |> File.read!() |> Jason.decode!() |> Map.get("components", [])
      end)

    {:ok, components: components, by_name: Map.new(components, &{&1["name"], &1})}
  end

  defp entry(component) do
    %{
      name: component["name"],
      global?: true,
      attrs: component["attrs"] || [],
      slots: component["slots"] || [],
      helpers: component["helpers"] || [],
      template: component["template"] || ""
    }
  end

  # The staged form belongs to the preview and nowhere else. These are the two functions the INSERT
  # handlers call, so asserting the negative here is asserting it about the document.
  describe "what an insert places" do
    alias MishkaCmsBuilder.PaletteEntry
    alias MishkaCmsBuilder.Wizard

    test "a dropped field is not wrapped in a form", %{components: components} do
      wrapped =
        for component <- components,
            entry = entry(component),
            Fields.field?(entry),
            markup = PaletteEntry.template(Map.put(entry, :render, nil), "Global"),
            markup =~ "<form",
            do: component["name"]

      assert wrapped == [],
             "a nested form is discarded by the HTML parser, silently:\n" <>
               Enum.join(wrapped, "\n")
    end

    test "the wizard composes a field without a form", %{components: components} do
      wrapped =
        for component <- components,
            entry = entry(component),
            Fields.field?(entry),
            Wizard.compose(entry, %{}, nil) =~ "<form",
            do: component["name"]

      assert wrapped == [], Enum.join(wrapped, "\n")
    end
  end
end
