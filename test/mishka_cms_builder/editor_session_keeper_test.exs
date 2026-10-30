# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.EditorSessionKeeperTest do
  @moduledoc """
  `MishkaCmsBuilder.EditorSession.Keeper`: a session's unwritten edits are written by a process
  that outlives whoever asked, one write at a time, and the session records what was written.

  The write here is a stand-in that answers a draft without touching the database, so what is
  pinned is the keeping itself — when a write happens, what it is handed, and what the session says
  afterwards.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias MishkaCmsBuilder.EditorSession
  alias MishkaCmsBuilder.EditorSession.Keeper
  alias MishkaCmsCore.Runtime.Authoring.Tree

  @moduletag :unit

  setup do
    {:ok, session} =
      EditorSession.open(%{section: "page", template: ~s(<div id="root"><p>a</p><p>b</p></div>)})

    on_exit(fn -> EditorSession.close(session.token) end)
    %{token: session.token}
  end

  defp edit(token) do
    {:ok, session} = EditorSession.fetch(token)
    p = session.tree |> Tree.walk() |> Enum.find(&(&1.tag == "p"))
    {:ok, session} = EditorSession.apply_op(token, %{"kind" => "delete", "node_id" => p.id})
    session
  end

  # A write that reports what it was handed and answers a draft named after the revision it carried.
  defp writing(test) do
    fn session ->
      send(test, {:writing, self(), session.revision})
      {:ok, %{id: "draft-#{session.revision}", label: "Sitting"}}
    end
  end

  # A write that waits to be let go, so a test can do something while it runs.
  defp held(test) do
    fn session ->
      send(test, {:holding, self(), session.revision})

      receive do
        :go -> {:ok, %{id: "held", label: "Sitting"}}
      end
    end
  end

  describe "a session holding unwritten edits" do
    test "is written once and marked saved as of what was written", %{token: token} do
      edited = edit(token)
      assert edited.dirty?

      assert {:ok, %{id: "draft-" <> _}, kept} = Keeper.keep(token, writing(self()))
      assert_received {:writing, _pid, revision}

      assert revision == edited.revision
      refute kept.dirty?
      assert kept.draft_id == "draft-#{revision}"
      assert kept.draft_label == "Sitting"
    end

    test "keeps the draft but stays unwritten when an edit lands during the write", %{
      token: token
    } do
      edit(token)
      test = self()
      keeping = Task.async(fn -> Keeper.keep(token, held(test)) end)
      assert_receive {:holding, writer, _revision}

      edit(token)
      send(writer, :go)

      assert {:ok, _draft, kept} = Task.await(keeping)
      assert kept.draft_id == "held"
      assert kept.dirty?, "the second edit is in no draft"
    end

    test "is written by a process that outlives its caller", %{token: token} do
      edit(token)
      test = self()
      caller = spawn(fn -> Keeper.keep(token, held(test)) end)
      assert_receive {:holding, writer, _revision}

      ref = Process.monitor(caller)
      Process.exit(caller, :kill)
      assert_receive {:DOWN, ^ref, :process, _caller, :killed}

      writer_ref = Process.monitor(writer)
      send(writer, :go)
      assert_receive {:DOWN, ^writer_ref, :process, _writer, _done}

      assert {:ok, %{dirty?: false, draft_id: "held"}} = EditorSession.fetch(token)
    end

    test "answers :running when the caller cannot wait, and the write still lands", %{
      token: token
    } do
      edit(token)
      test = self()

      assert Keeper.keep(token, held(test), 50) == :running
      assert_receive {:holding, writer, _revision}

      writer_ref = Process.monitor(writer)
      send(writer, :go)
      assert_receive {:DOWN, ^writer_ref, :process, _writer, _done}

      assert {:ok, %{dirty?: false, draft_id: "held"}} = EditorSession.fetch(token)
    end
  end

  describe "one write at a time" do
    test "a second keep waits for the first, then finds nothing left to write", %{token: token} do
      edit(token)
      test = self()
      first = Task.async(fn -> Keeper.keep(token, held(test)) end)
      assert_receive {:holding, writer, _revision}

      second = Task.async(fn -> Keeper.keep(token, writing(test)) end)
      refute_receive {:writing, _pid, _revision}, 300, "the second write ran beside the first"

      send(writer, :go)
      assert {:ok, _draft, _kept} = Task.await(first)
      assert {:clean, %{draft_id: "held"}} = Task.await(second, 15_000)
      refute_received {:writing, _pid, _revision}
    end

    test "and writes what the first did not carry", %{token: token} do
      edit(token)
      test = self()
      first = Task.async(fn -> Keeper.keep(token, held(test)) end)
      assert_receive {:holding, writer, _revision}

      %{revision: newest} = edit(token)
      second = Task.async(fn -> Keeper.keep(token, writing(test)) end)

      send(writer, :go)
      assert {:ok, _draft, _kept} = Task.await(first)
      assert {:ok, _draft, kept} = Task.await(second, 15_000)
      assert_received {:writing, _pid, ^newest}
      refute kept.dirty?
    end
  end

  describe "nothing to write" do
    test "a session with no unwritten edits is left alone", %{token: token} do
      assert {:clean, %{dirty?: false}} = Keeper.keep(token, writing(self()))
      refute_received {:writing, _pid, _revision}
    end

    test "a write that does not happen is answered as it came, and the session stays unwritten",
         %{token: token} do
      edit(token)

      assert Keeper.keep(token, fn _session -> {:error, :refused} end) == {:error, :refused}
      assert {:ok, %{dirty?: true}} = EditorSession.fetch(token)
    end

    test "a write that crashes is answered, not raised", %{token: token} do
      edit(token)

      # The crash report is the task supervisor's, and expected.
      capture_log(fn ->
        assert {:error, {:exit, _reason}} = Keeper.keep(token, fn _session -> raise "boom" end)
      end)

      assert {:ok, %{dirty?: true}} = EditorSession.fetch(token)
    end

    test "a session that is not there answers :error" do
      assert Keeper.keep("nosuchsessiontokennosuchsession0", writing(self())) == :error
    end
  end
end
