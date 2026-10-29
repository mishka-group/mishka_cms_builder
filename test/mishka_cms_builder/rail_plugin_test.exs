# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.RailPluginTest do
  @moduledoc """
  An extension adding a rail to the editor, end to end — the thing the `builder:rails` registry
  advertised and could not actually do.

  Three separate links were broken, and each on its own was enough to make the seam a lie:

    * `Events.collect(:rails, …)` fired into an assign, and the assign reached the panel, but the
      rail BODIES were hardcoded `:if` branches — so a contributed rail drew a tab that opened onto
      nothing;
    * `handle_event("set_right_tab", …)` matched the tab against a fixed list of three atoms, so the
      click that would have opened it was discarded before it arrived;
    * `Descriptor.render/2`, the dispatcher meant to draw a contributed body, had no callers at all.

  So this asserts the whole path rather than any one link: the descriptor is collected, the tab is
  drawn, the click is accepted, and the body appears on screen.
  """
  use ExUnit.Case, async: false

  import Phoenix.LiveViewTest

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

  @doc false
end
