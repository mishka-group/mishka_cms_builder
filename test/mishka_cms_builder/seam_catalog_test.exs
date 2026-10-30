# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.SeamCatalogTest do
  @moduledoc """
  The editor's share of the core's seam catalog (`MishkaCmsCore.Builder.Events`) really fires.

  The catalog lives in the core, so a plugin can be written against it without the editor, but
  most of it is fired here. The core's `MishkaCmsCore.Builder.SeamCatalogTest` checks the core's own
  events against the core's source and names the rest as the editor's; this checks that rest against
  the editor's source. A registry nobody collects, or a seam nobody calls, behaves like a working one
  until a plugin registers on it and nothing happens, with no error to read.

  The two lists are the core test's `@editor_registries` and `@editor_named`. A seam that moves
  between the core and the editor changes both.
  """
  use ExUnit.Case, async: true

  alias MishkaCmsCore.Builder.Events

  @moduletag :unit

  @editor_registries ~w(components blocks elements inspector_sections rails studio_tabs
                        canvas_toolbar commands audit_checks page_starters conditions
                        mention_sources)a

  @editor_named ~w(history_query before_draft_save after_draft_save before_comment after_comment
                   before_code_apply before_token_set before_class_save before_element_css
                   after_element_css before_ask containment examples preset_choices
                   toolbar_invoked form_customized form_created)a

  defp source, do: "lib/**/*.ex" |> Path.wildcard() |> Enum.map_join("\n", &File.read!/1)

  describe "the editor's share against its code" do
    setup do
      %{source: source()}
    end

    test "every registry the core names as the editor's is collected here", %{source: source} do
      uncollected =
        Enum.reject(@editor_registries, &Regex.match?(~r/collect\w*\(\s*:#{&1}\b/, source))

      assert uncollected == [],
             "named as the editor's but never collected: #{inspect(uncollected)}"
    end

    test "every named seam the core names as the editor's is called here", %{source: source} do
      unfired = Enum.reject(@editor_named, &Regex.match?(~r/Events\.#{&1}\(/, source))

      assert unfired == [], "named as the editor's but never fired: #{inspect(unfired)}"
    end
  end

  describe "the share against the catalog" do
    test "every registry of the share is one the catalog declares" do
      assert @editor_registries -- Map.keys(Events.registries()) == []
    end

    test "every named seam of the share is one the catalog exports" do
      exported = Events.__info__(:functions) |> Enum.map(&elem(&1, 0)) |> MapSet.new()

      assert Enum.reject(@editor_named, &MapSet.member?(exported, &1)) == []
    end
  end
end
