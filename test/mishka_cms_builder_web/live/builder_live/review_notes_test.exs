# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.ReviewNotesTest do
  @moduledoc """
  Review notes between two people: following a mention to the note it is about, a thread whose times
  move on by themselves, who the `@` list offers first, and telling the people in a session apart.
  """
  use MishkaCmsBuilder.LiveCase

  alias MishkaCmsCore.Notify.Notification

  # Where a mention's notification points: the page's editor, at the note.
  defp note_url(page, id), do: "/admin/dashboard/runtime/builder/page/#{page.id}?note=#{id}"

  # The composer is a Gervaz form; the thread re-reads asynchronously, so `render_async/1` is the wait.
  defp post_note(view, body, type) do
    view
    |> element("#pb-comment-form")
    |> render_submit(%{"form" => %{"body" => body, "type" => type}})

    render_async(view)
  end

  defp notes(site, document) do
    MishkaCmsBuilder.Review.list(%{site_id: site.id, section: :page, document_id: document.id})
  end

  defp feed(user) do
    Notification
    |> Ash.Query.for_read(:feed)
    |> Ash.read!(actor: user, tenant: user.site_id, page: false)
  end

  # A second admin, signed in on their own connection.
  defp signed_in(email) do
    user = create_admin(email)
    {user, log_in(build_conn_for_host(), user)}
  end

  # A note on the page's heading, written by the signed-in admin through the editor.
  defp heading_note!(conn, page, site, body) do
    {:ok, view, _html} = open_builder(conn, page)
    render_click(view, "select", %{"id" => node_with_tag(view, "h1").id})
    render_click(view, "open_sheet", %{"sheet" => "review"})
    post_note(view, body, "question")

    [note | _older] = notes(site, page)
    note
  end

  defp open_at(conn, path) do
    {:ok, view, _html} = live(conn, path)
    render_async(view)
    view
  end

  describe "following a mention's link" do
    test "opens the Review sheet at the note, with the element it is about selected", %{
      conn: conn,
      page: page,
      site: site
    } do
      {named, named_conn} = signed_in("named.reader@example.com")
      note = heading_note!(conn, page, site, "@named.reader@example.com is this heading right?")

      [mention | _rest] = feed(named)
      assert mention.link == note_url(page, note.id)

      view = open_at(named_conn, mention.link)

      assert live_assigns(view).sheet == :review
      assert has_element?(view, ~s([data-role="pb-review-thread"]))
      assert editor(view).selection == node_with_tag(view, "h1").id
      assert has_element?(view, ~s(#pb-comment-#{note.id}[data-focused="true"]))
      assert has_element?(view, ~s(#pb-comment-#{note.id}[tabindex="-1"]))
    end

    test "marks a reply that named the reader, inside its thread", %{
      conn: conn,
      page: page,
      site: site
    } do
      {named, named_conn} = signed_in("replied.reader@example.com")
      {:ok, view, _html} = open_builder(conn, page)
      render_click(view, "open_sheet", %{"sheet" => "review"})
      post_note(view, "A question about the page", "question")
      [question] = notes(site, page)

      render_click(view, "reply_to_comment", %{"id" => question.id})

      view
      |> element("#pb-comment-form")
      |> render_submit(%{"form" => %{"body" => "@replied.reader@example.com what do you think?"}})

      [%{replies: [reply]}] = notes(site, page)
      [mention | _rest] = feed(named)
      assert mention.link == note_url(page, reply.id)

      opened = open_at(named_conn, mention.link)

      assert has_element?(opened, ~s(#pb-comment-#{reply.id}[data-focused="true"]))
      refute has_element?(opened, ~s(#pb-comment-#{question.id}[data-focused]))
    end

    test "a note about the whole page opens the thread and selects nothing", %{
      conn: conn,
      page: page,
      site: site
    } do
      {:ok, view, _html} = open_builder(conn, page)
      render_click(view, "open_sheet", %{"sheet" => "review"})
      post_note(view, "About the page", "information")
      [note] = notes(site, page)

      {_reader, reader_conn} = signed_in("page.reader@example.com")
      opened = open_at(reader_conn, note_url(page, note.id))

      assert live_assigns(opened).sheet == :review
      assert has_element?(opened, ~s(#pb-comment-#{note.id}[data-focused="true"]))
      refute editor(opened).selection
    end

    test "a deleted, unknown or malformed note opens the plain editor and says nothing", %{
      conn: conn,
      page: page,
      site: site
    } do
      {:ok, view, _html} = open_builder(conn, page)
      render_click(view, "open_sheet", %{"sheet" => "review"})
      post_note(view, "Soon gone", "information")
      [note] = notes(site, page)
      render_click(view, "delete_comment", %{"id" => note.id})
      assert notes(site, page) == []

      for id <- [note.id, Ecto.UUID.generate(), "not-a-note"] do
        {_reader, reader_conn} = signed_in("stale.#{System.unique_integer([:positive])}@x.test")
        view = open_at(reader_conn, note_url(page, id))

        assert live_assigns(view).sheet == :none, "#{inspect(id)} opened the Review sheet"
        refute live_assigns(view)[:focused_note]
        refute render(view) =~ "no longer"
        assert node_with_tag(view, "h1"), "the editor itself still opens"
      end
    end

    test "a note on another document is not opened on this one", %{
      conn: conn,
      page: page,
      site: site
    } do
      elsewhere = create_page!(site_id: site.id, name: "elsewhere-#{System.unique_integer()}")
      note = heading_note!(conn, elsewhere, site, "On the other page")

      {_reader, reader_conn} = signed_in("wrong.page@example.com")
      view = open_at(reader_conn, note_url(page, note.id))

      assert live_assigns(view).sheet == :none
      refute live_assigns(view)[:focused_note]
    end
  end

end
