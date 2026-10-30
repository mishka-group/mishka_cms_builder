# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.EditorSession.Keeper do
  @moduledoc """
  Writes the edits an editing session holds and no draft does — on every change, on the way out of
  the editor, and before a reopened session is moved off its draft.

  ## Why the session, and not the LiveView

  An edit lands in the session first: `MishkaCmsBuilder.EditorSession` stores it in ETS, where it
  outlives the LiveView that made it. It reaches a draft row a moment later, when the chrome writes
  it — and that moment used to belong to the LiveView. The write ran in a task linked to it, and
  what the write settled (the draft it made, the revision it carried) was recorded by the LiveView
  when the answer came back. A tab closed, a page left or a socket dropped inside that moment took
  the write down with the LiveView, and the next visit detached the session from its draft and threw
  the unwritten edit away with the tree it replaced. A drop followed by closing the tab at once was
  enough.

  So a write here:

    * runs in a process of its own under `MishkaCmsCore.Runtime.TaskSupervisor`, linked to nobody,
      so the caller exiting does not stop it;
    * records what it wrote on the session itself — `EditorSession.mark_saved/2` with the draft and
      the revision it serialized — so the session knows its draft even when no LiveView is left to
      hear the answer;
    * waits its turn: one write per session at a time, and each reads the session as stored when its
      turn comes. A write asked for on the way out therefore follows the one already running and
      writes only what that one did not carry, and an older document never lands over a newer one.

  A session with nothing unwritten is left alone, so asking costs one ETS read.
  """

  alias MishkaCmsBuilder.EditorSession

  @supervisor MishkaCmsCore.Runtime.TaskSupervisor

  @typedoc "What a keep did: wrote, found nothing to write, or did not write."
  @type outcome ::
          {:ok, struct(), EditorSession.t()}
          | {:clean, EditorSession.t()}
          | :running
          | :error
          | term()

  @doc """
  Writes `token`'s session with `write` when it holds edits no draft has, and marks it saved as of
  the revision written.

  `write` receives the session as stored when this write's turn comes, and answers `{:ok, draft}` for
  a draft it wrote; anything else is a write that did not happen and is answered as it came.

  Answers `{:ok, draft, session}` with the session as marked, `{:clean, session}` when there was
  nothing to write, `:error` when there is no such session, `{:error, {:exit, reason}}` when the write
  crashed, and `:running` when `timeout` passed first — the write then goes on without the caller,
  and still records what it wrote.
  """
  @spec keep(String.t(), (EditorSession.t() -> {:ok, struct()} | term()), timeout()) :: outcome()
  def keep(token, write, timeout \\ :infinity)
      when is_binary(token) and is_function(write, 1) do
    work = MishkaGervaz.Messages.in_caller_locale(fn -> in_turn(token, write) end)
    task = Task.Supervisor.async_nolink(@supervisor, work)

    case Task.yield(task, timeout) do
      {:ok, outcome} -> outcome
      {:exit, reason} -> {:error, {:exit, reason}}
      nil -> running(task)
    end
  end

  # LEFT TO FINISH, not stopped. The caller is usually a LiveView on its way out and cannot wait any
  # longer; the write it asked for is the one thing that must still happen.
  defp running(task) do
    Task.ignore(task)
    :running
  end

  # ONE WRITER PER SESSION. The lock is the session's, so the chrome's write, the one asked for on
  # the way out and the one a reopen asks for queue behind each other instead of racing to the row.
  defp in_turn(token, write),
    do: :global.trans({{__MODULE__, token}, self()}, fn -> now(token, write) end, [node()])

  # READ AFTER THE TURN COMES, so whatever the previous writer carried is already marked and only
  # the rest is written.
  defp now(token, write) do
    case EditorSession.fetch(token) do
      {:ok, %{dirty?: false} = session} -> {:clean, session}
      {:ok, session} -> session |> write.() |> settled(token, session.revision)
      :error -> :error
    end
  end

  defp settled({:ok, %{id: id} = draft}, token, revision) do
    case EditorSession.mark_saved(token,
           stage: :draft,
           draft_id: id,
           draft_label: Map.get(draft, :label),
           as_of: revision
         ) do
      {:ok, session} -> {:ok, draft, session}
      _gone -> :error
    end
  end

  defp settled(unwritten, _token, _revision), do: unwritten
end
