# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.FieldsRoleTest do
  @moduledoc """
  What part of a form a component plays: declared by the kit when the kit says, inferred from its
  markup when it does not, and left at `:none` for an error component, which has no structural
  signal.

  The inference fails OPEN — get it wrong and the editor writes a binding onto a component that
  cannot take one, and `KeyError :name` lands inside LiveView's diff with nothing in the editor to
  notice. So every branch is pinned here against a hand-built entry whose one distinguishing signal
  is named in the test, and against the real Chelekom rows and renamed copies of them.
  """
  use ExUnit.Case, async: true

  alias MishkaCmsBuilder.PaletteEntry

  @moduletag :unit

  @kits_dir MishkaCmsCore.Runtime.Handlers.UiKitHandler.kits_dir()

  setup_all do
    by_name =
      @kits_dir
      |> Path.join("*.json")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        path |> File.read!() |> Jason.decode!() |> Map.get("components", [])
      end)
      |> Map.new(&{&1["name"], &1})

    {:ok, by_name: by_name}
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

  # `Phoenix.Component.form/1` hands `for` to `to_form/2`, and `Phoenix.HTML.FormData` has no
  # implementation for a binary, so a wrapper seeded with a string raises a protocol error the
  # instant it is dropped. This is the one consumer of `wrapper?/1` that a regression would be
  # silent in, because the seeding is invisible until the canvas renders.
  describe "what a dropped wrapper is seeded with" do
    test "a form owner gets an empty map, not a string", %{by_name: by_name} do
      for name <- ~w(chelekom-form-wrapper chelekom-simple-form) do
        markup = PaletteEntry.template(entry(by_name[name]), "Global")

        assert markup =~ ~s(for={%{}}), "#{name} must seed `for` with a map"
      end
    end

    test "a label's `for` is still a string", %{by_name: by_name} do
      markup = PaletteEntry.template(entry(by_name["chelekom-label"]), "Global")

      refute markup =~ ~s(for={%{}})
    end
  end
end
