# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.ClosingTest do
  @moduledoc """
  The editor going away with an edit it has not written yet — a tab closed, a page left, a socket
  dropped — and what is in the draft afterwards.

  An edit lands in the editing session before any draft holds it, and the session outlives the
  LiveView. What used to belong to the LiveView alone was the write in between: it ran in a task
  linked to the LiveView, so the LiveView going took the write with it, and the next visit moved
  the session off its draft and threw the unwritten edit away with the tree it replaced. Closing the
  tab straight after a drop was enough to lose the drop.

  Each test leaves the editor one way — killed, with nothing run on the way out; or stopped, which
  runs `terminate/2` the way a closed tab does — at a moment no draft holds the last edit, and then
  reads the draft.
  """
  use MishkaCmsBuilder.LiveCase

  # The LiveView is linked to this process through the test's client, and both ways out below end it
  # with a reason that is not `:normal`.
  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  # GONE WITHOUT A WORD. A kill runs nothing on the way out, like a crashed node or a process taken
  # down by something it was linked to.
  defp kill(view) do
    ref = Process.monitor(view.pid)
    Process.exit(view.pid, :kill)
    assert_receive {:DOWN, ^ref, :process, _pid, :killed}
  end

  # A CLOSED TAB. The socket's process goes, and the LiveView stops with `{:shutdown, :closed}` —
  # which runs `terminate/2`. Synchronous, so whatever the way out does has been done when it returns.
  defp close(view), do: GenServer.stop(view.pid, {:shutdown, :closed})

  # AN EDIT THE CHROME HAS NOT HEARD OF. The canvas is the LiveView that applies a drop, and the
  # chrome writes the draft only when the session's broadcast reaches it — so with the chrome held,
  # the edit is in the session and in nothing else.
  defp unheard_edit(view, tag) do
    {token, node} = {token(view), node_with_tag(view, tag)}
    :sys.suspend(view.pid)
    {:ok, _session} = EditorSession.apply_op(token, %{"kind" => "delete", "node_id" => node.id})
  end

  # THE EDIT ALSO STARTED A HISTORY FLUSH, and a process killed while it queries takes the test's
  # shared database connection down with it. The draft write is held at its gate, before any query.
  defp history_flushed(view, tries \\ 125) do
    case live_assigns(view).history_flushing? do
      false ->
        :ok

      true when tries > 0 ->
        Process.sleep(40)
        history_flushed(view, tries - 1)

      true ->
        flunk("the history flush never finished")
    end
  end

  defp the_draft(page, actor) do
    assert [draft] = Drafts.list("page", page, actor)
    draft
  end

  # THE WRITE IS NOT THIS PROCESS'S, so it is waited for the way a reader would: until the session
  # says what it says once the write has landed.
  defp settled(token, tries \\ 125) do
    case EditorSession.fetch(token) do
      {:ok, %{dirty?: false} = session} ->
        session

      _still_writing when tries > 0 ->
        Process.sleep(40)
        settled(token, tries - 1)

      other ->
        flunk("the session never settled: #{inspect(other, limit: 3)}")
    end
  end

  describe "a draft write running when the editor goes" do
    test "finishes, and the draft holds the edit it carried", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)
      _draft_id = autosave!(view)
      {token, recorded} = {token(view), actor(view)}

      pause_draft_writes()
      render_click(view, "op", %{"kind" => "delete", "node_id" => node_with_tag(view, "p").id})
      assert_receive {:draft_write_paused, writing}

      history_flushed(view)
      kill(view)
      send(writing, :release)

      refute settled(token).dirty?
      refute the_draft(page, recorded).template =~ "<p", "the write the drop started landed"
    end
  end

  describe "an edit no write has carried yet" do
    test "is written as the editor closes", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)
      draft_id = autosave!(view)
      {token, recorded} = {token(view), actor(view)}

      unheard_edit(view, "p")
      close(view)

      draft = the_draft(page, recorded)
      assert draft.id == draft_id, "the sitting's own draft, not a second one"
      refute draft.template =~ "<p", "the edit was written on the way out"
      refute elem(EditorSession.fetch(token), 1).dirty?
    end

    test "is written before a reopened session leaves its draft", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)
      _draft_id = autosave!(view)
      recorded = actor(view)

      unheard_edit(view, "p")
      kill(view)

      {:ok, again, _html} = open_builder(conn, page)

      assert node_with_tag(again, "p"), "the reopened editor is on the live page"
      assert has_element?(again, "#pb-inherited-bar")
      refute the_draft(page, recorded).template =~ "<p", "the draft it offers holds the edit"

      again |> element("#pb-inherited-continue") |> render_click()
      refute node_with_tag(again, "p"), "and Carry on brings it back"
    end

    # THE SITTING'S FIRST WRITE never landed, so there is no draft to detach from: the session is
    # picked back up as it is, with the edit on screen, and that pick-up writes it.
    test "made before the sitting's first write is back on screen when the page reopens", %{
      conn: conn,
      page: page
    } do
      {:ok, view, _html} = open_builder(conn, page)
      recorded = actor(view)

      unheard_edit(view, "p")
      kill(view)

      {:ok, again, _html} = open_builder(conn, page)

      refute node_with_tag(again, "p"), "the edit is on screen"
      refute has_element?(again, "#pb-inherited-bar")
      refute settled(token(again)).dirty?
      refute the_draft(page, recorded).template =~ "<p", "and written as the sitting's draft"
    end

    test "made in publish mode is not written on the way out", %{conn: conn, page: page} do
      {:ok, view, _html} = open_builder(conn, page)
      recorded = actor(view)
      render_click(view, "set_stage", %{"stage" => "published"})
      render_click(view, "op", %{"kind" => "delete", "node_id" => node_with_tag(view, "h1").id})

      close(view)

      assert Drafts.list("page", page, recorded) == [], "publish mode writes nothing but the page"
    end
  end
end
