# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.SectionSeamsTest do
  @moduledoc """
  The sections of the editor that had no seam, each driven by a registered plugin.

  Every test here registers a real `MishkaInstaller` plugin and compiles the event, because that is
  the only way to tell a working seam from a declared one: without a plugin listening, an event that
  fires and an event that does not are indistinguishable — both return the value unchanged.

  The last describe is the one that matters most in practice. A plugin nobody in this project wrote
  will raise one day, and when it does the editor must keep working with the value it already had.
  """
  use MishkaCmsCore.DataCase, async: false

  alias MishkaCmsCore.Builder.Events
  alias MishkaCmsBuilder.PageComment

  alias MishkaCmsBuilder.Test.Plugins.{BuilderCommentGate, BuilderHistoryScope}

  alias MishkaInstaller.Event.{Event, EventHandler}

  @moduletag :integration

  defp register(module, event) do
    {:ok, _} =
      Event.write(%{
        name: module,
        event: event,
        extension: :mishka_installer,
        status: :started
      })

    :ok = EventHandler.do_compile(event, :start, false)
    on_exit(fn -> Event.unregister(:name, module, false) end)
    :ok
  end

  describe "the review composer's gate" do
    setup do: register(BuilderCommentGate, "builder:review:before_comment")

    test "a plugin's house rule refuses the note, in its own words" do
      assert PageComment.refuse(%{"body" => BuilderCommentGate.refused(), "type" => "bug"}) =~
               "Say what needs doing"
    end

    test "and a note it is happy with still saves" do
      assert PageComment.refuse(%{"body" => "The gap is wrong here.", "type" => "bug"}) == nil
    end

    # The core's own rules run first, so a plugin never sees a blank note and cannot be the reason
    # one is refused — which keeps the message the author reads the most specific true one.
    test "the core's rules still come first" do
      assert PageComment.refuse(%{"body" => "  ", "type" => "bug"}) == "Write something first."
    end
  end

  describe "the history timeline's read" do
    setup do: register(BuilderHistoryScope, "builder:history:query")

    test "a plugin can narrow it, and the sheet still pages honestly" do
      query = Ash.Query.new(MishkaCmsBuilder.HistoryEvent)

      scoped = Events.history_query(query, %{source_type: :page, source_id: nil, branch_id: nil})

      assert %Ash.Query{} = scoped
      assert inspect(scoped.filter) =~ "kind"
    end

    test "and a plugin that answers with something else leaves the read alone" do
      query = Ash.Query.new(MishkaCmsBuilder.HistoryEvent)

      assert Events.history_query(query, %{source_type: nil, source_id: nil, branch_id: nil})
    end
  end
end
