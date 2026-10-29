# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.UiKit.AuthoringExampleTest do
  @moduledoc """
  The bundle in `priv/cms_ui_kits/authoring/` is the answer to "how do I import my own component",
  and it is executable rather than illustrative.

  ## Why the example is a test

  A third-party developer's first contact with this CMS is a JSON file they have to get right with no
  feedback loop: a bundle that installs is not yet a bundle that renders, and the ways it silently
  half-works — an undeclared assign, a `phx-hook` naming a key nothing builds, an opener the editor
  cannot see — all surface much later, on somebody's canvas, as a red box.

  So every claim the README makes is asserted here against the file it points at. A guide that has
  drifted from the thing it documents is worse than no guide, and prose cannot drift if the prose is
  checked.
  """
  use MishkaCmsCore.DataCase, async: false

  alias MishkaCmsBuilder.PaletteEntry

  require Ash.Query

  @moduletag :integration

  @dir Path.join([:code.priv_dir(:mishka_cms_core), "cms_ui_kits", "authoring"])
  @bundle Path.join(@dir, "acme.json")

  defp bundle, do: @bundle |> File.read!() |> Jason.decode!()

  describe "the guide and the file it points at" do
    # RULE 6. Declare nothing and the author is offered the generic `JS.show`, which on anything more
    # elaborate than `display:none` reveals the wrong half — a backdrop with no panel under it.
    test "the component that opens declares how, on its root, where the editor reads it" do
      panel = Enum.find(bundle()["components"], &(&1["name"] == "acme-panel"))

      entry = %{name: panel["name"], template: panel["template"]}

      assert PaletteEntry.opens(entry) == %{
               "show" => "data-pb-open",
               "hide" => "data-pb-close"
             }

      assert PaletteEntry.concealed?(entry),
             "a component that declares an opener is the one the canvas shows open while editing"
    end
  end
end
