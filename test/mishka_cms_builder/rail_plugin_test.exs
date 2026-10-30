# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.RailPluginTest do
  @moduledoc """
  The rails the editor itself contributes to the `builder:rails` registry. They are collected beside
  the ones an extension adds, so the editor keeps its layers, assistant and audit tabs.
  """
  use ExUnit.Case, async: false

  alias MishkaCmsCore.Builder.{Descriptor, Events}

  @moduletag :unit

  describe "the descriptor an extension contributes" do
    test "and the core's own rails are still there when it is added" do
      collected = Events.collect(:rails, MishkaCmsBuilderWeb.Live.Panels.core_rails())
      keys = Enum.map(collected, &Descriptor.key/1)

      assert "layers" in keys
      assert "assistant" in keys
      assert "audit" in keys
    end
  end
end
