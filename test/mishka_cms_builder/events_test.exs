# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.EventsTest do
  @moduledoc """
  What the builder contributes to a lookup through the plugin surface: a plugin that adds a block
  to the palette is found by its id, beside the core's own blocks, in the same call.
  """
  use MishkaCmsCore.DataCase, async: false

  alias MishkaCmsBuilder.Blocks
  alias MishkaCmsBuilder.Test.Plugins.BuilderBlockPlugin
  alias MishkaCmsCore.Builder.Events
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
  end
end
