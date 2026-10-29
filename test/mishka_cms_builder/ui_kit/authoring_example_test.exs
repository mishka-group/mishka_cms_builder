# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.UiKit.AuthoringExampleTest do
  @moduledoc """
  The editor's side of the example bundle in the core's `priv/cms_ui_kits/authoring/`.

  The bundle is the answer to "how do I import my own component", and the guide next to it says a
  component that opens and closes declares how on its root, where the editor reads it: an author who
  wires a button to it is then offered the component's own verbs rather than the generic `JS.show`,
  which on anything more elaborate than `display:none` reveals the wrong half. The core asserts the
  rest of the guide against the file; the editor's reading of that declaration is asserted here.
  """
  use MishkaCmsCore.DataCase, async: false

  alias MishkaCmsBuilder.PaletteEntry

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
