# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.EventsTest do
  @moduledoc """
  The builder's plugin surface: ten registries, the lifecycle announcements, the node transform
  seams and the save/publish gates.

  The gates matter most. A `builder:save:before` hook that cannot actually stop a write would be
  decoration, and the whole point of putting content lint and link checking there is that a refusal
  is binding. That is asserted end to end against the live editor in the `builder_live/` tests;
  here the contract itself is pinned down.
  """
  use MishkaCmsCore.DataCase, async: false

  alias MishkaCmsCore.Builder.Events
  alias MishkaCmsBuilder.Blocks
  alias MishkaCmsCore.Runtime.Authoring.Icons.Bundled
  alias MishkaCmsBuilder.Test.Plugins.BuilderBlockPlugin
  alias MishkaInstaller.Event.{Event, EventHandler}

  defp register!(plugin, event) do
    {:ok, _} =
      Event.write(%{
        name: plugin,
        event: event,
        extension: :mishka_installer,
        status: :started
      })

    :ok = EventHandler.do_compile(event, :start, false)
    on_exit(fn -> Event.unregister(:name, plugin, false) end)
  end

  # A CARD IS CLICKED BACK BY ITS ID. The palette and the empty-page chooser draw the merged list, so
  # the lookup behind the click reads the merged list too — and with the same seed, because the two
  # passes must hand the plugin one payload, not two. Pinned here rather than only through the
  # editor: `canvas_live` and `editor_session` are the callers, this is the contract.
  describe "fetch/3, with a plugin contributing a block" do
    setup do
      register!(BuilderBlockPlugin, "builder:blocks")
      %{block: BuilderBlockPlugin.block()}
    end

    test "the contributed entry answers its own id", %{block: block} do
      assert Events.fetch(:blocks, Blocks.all(), block.id) == block
    end

    # Which is why a caller needs no second lookup of its own: fired with `[]`, this answers nil for
    # every id the core library owns.
    test "a core entry answers from the same call" do
      assert %{id: "hero-centred"} = Events.fetch(:blocks, Blocks.all(), "hero-centred")
    end

    test "an id in neither list answers nil" do
      assert Events.fetch(:blocks, Blocks.all(), "no-such-block") == nil
    end

    # `entry_id/1` answers a bare module with itself, because the icon libraries ARE modules. Nothing
    # resolves those by id, and an entry of that shape must stay inert rather than reach a caller
    # that will read `:template` off it.
    test "an entry that is not a map is not an answer" do
      assert Events.fetch(:icon_libraries, [Bundled], Bundled) == nil
    end

    test "an unknown registry raises rather than silently answering nil" do
      assert_raise FunctionClauseError, fn -> Events.fetch(:not_a_registry, [], "x") end
    end
  end
end
