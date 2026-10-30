# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Presence do
  @moduledoc """
  Who else is in this editing session — real `Phoenix.Presence` on the session's own PubSub topic.

  The prototype drew three hardcoded avatars (JD, AB, CD). That is worse than showing none: it tells
  an author their colleagues are watching when nobody is, and it hides the one case that actually
  matters — two people editing the same page, where the editor is last-write-wins at the op level.

  Tracking costs nothing here because the topic already exists: both LiveViews of a session are
  subscribed to it for document updates, so presence rides along.
  """
  use Phoenix.Presence,
    otp_app: :mishka_cms_builder,
    pubsub_server: MishkaCmsCore.PubSub

  use Gettext, backend: MishkaCmsCore.Gettext

  alias MishkaCmsCore.Accounts.Helper
  alias MishkaCmsCore.Accounts.User
  alias MishkaCmsBuilder.EditorSession

  require Ash.Query

  @doc """
  Announces a user as editing `token`. Safe to call with no user — an anonymous mount tracks nothing.

  The entry carries the user's id, initials and whether it is a master, never its email.
  """
  @spec join(String.t(), map() | nil) :: {:ok, binary()} | {:error, term()} | :ignore
  def join(_token, nil), do: :ignore

  def join(token, user) do
    track(self(), EditorSession.topic(token), user.id, %{
      id: user.id,
      master?: Helper.master_user?(user),
      initials: initials(user),
      at: System.system_time(:second)
    })
  end

  @doc "Everyone currently in the session, one entry per person however many tabs they have open."
  @spec editors(String.t()) :: [map()]
  def editors(token) do
    token
    |> EditorSession.topic()
    |> list()
    |> Enum.map(fn {_id, %{metas: [meta | _rest]}} -> meta end)
    |> Enum.sort_by(& &1.at)
  end

  @doc """
  Everyone except `user` — the avatars worth showing, since your own presence is not news.

  A master's avatar reads the first letter of `MishkaCmsCore.Accounts.Helper.label(:master)`, "M",
  unless `user` is a master too.

  Each entry also carries `:name`, who it is as `user` may call them — the same answer a review note's
  byline gives (`name/2`): the address of somebody `user` may see, "Master" for a master a site user
  may not. Two people with one set of initials are told apart by it. It is read from the accounts,
  in one read for the whole session, because the entry itself carries no address.
  """
  @spec others(String.t(), map() | nil) :: [map()]
  def others(token, nil), do: token |> editors() |> named(nil)

  def others(token, user) do
    token
    |> editors()
    |> Enum.reject(&(&1.id == user.id))
    |> named(user)
  end

  defp named([], _viewer), do: []

  defp named(editors, viewer) do
    accounts = accounts(Enum.map(editors, & &1.id))

    Enum.map(editors, fn editor ->
      editor
      |> seen_by(viewer)
      |> Map.put(:name, who(Map.get(accounts, editor.id), editor.master?, viewer))
    end)
  end

  defp accounts(ids) do
    User
    |> Ash.Query.filter(id in ^ids)
    |> Ash.Query.select([:id, :email, :site_id])
    |> Ash.read(authorize?: false)
    |> case do
      {:ok, users} -> Map.new(users, &{&1.id, &1})
      {:error, _reason} -> %{}
    end
  end

  defp seen_by(%{master?: true} = editor, viewer) do
    case Helper.master_user?(viewer) do
      true -> editor
      false -> %{editor | initials: String.first(Helper.label(:master))}
    end
  end

  defp seen_by(editor, _viewer), do: editor

  @doc """
  Who `user` is to `viewer`: their address when `viewer` may see it, "Master" for a master when not,
  "Unknown" for anyone else — what `MishkaCmsBuilderWeb.Templates.ReviewComments` writes on a note by
  them, so a person's avatar and their notes are named alike.
  """
  @spec name(map() | nil, map() | nil) :: String.t()
  def name(user, viewer), do: who(user, Helper.master_user?(user), viewer)

  defp who(user, master?, viewer),
    do: Helper.who(Helper.visible_to(user, viewer), master?, :unknown)

  @doc ~S"""
  Two letters for an avatar chip, from the local part of an email: `"ada.love@x.com"` gives `"AL"`.

  An address is an `Ash.CiString`, not a binary, so it is stringified rather than guarded on —
  guarding on `is_binary/1` silently produced "?" for every real user.
  """
  @spec initials(map()) :: String.t()
  def initials(%{email: email}) when not is_nil(email) do
    email
    |> to_string()
    |> String.split("@")
    |> hd()
    |> String.split(~r/[._\-+]/, trim: true)
    |> Enum.map(&String.first/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(2)
    |> Enum.map_join(&String.upcase/1)
    |> fallback()
  end

  def initials(_user), do: "?"

  defp fallback(""), do: "?"
  defp fallback(initials), do: initials

  @doc ~S"""
  A display name for a review byline: the local part of the address, `"Someone"` with no user.

  Accounts carry no separate name field, so the address is what there is. The domain is dropped
  because a comment thread reads better as "ada.love" than as a full address.
  """
  @spec display_name(map() | nil) :: String.t()
  def display_name(%{email: email}) when not is_nil(email) do
    email |> to_string() |> String.split("@") |> hd() |> named()
  end

  def display_name(_user), do: gettext("Someone")

  defp named(""), do: gettext("Someone")
  defp named(name), do: name
end
