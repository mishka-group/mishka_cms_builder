# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilderWeb.Live.BuilderLive.ReviewNotesTest do
  @moduledoc """
  Review notes between two people: following a mention to the note it is about, a thread whose times
  move on by themselves, who the `@` list offers first, and telling the people in a session apart.
  """
  use MishkaCmsBuilder.LiveCase

  alias MishkaCmsBuilder.Presence
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

  describe "a note's time" do
    # The thread draws "now", "4m ago", "3h ago"; nothing but a change to the rows re-drew it, so
    # the author read "now" for as long as nobody else wrote.
    test "moves on while the thread stays open", %{conn: conn, page: page, site: site} do
      {:ok, view, _html} = open_builder(conn, page)
      render_click(view, "open_sheet", %{"sheet" => "review"})
      post_note(view, "Fresh", "information")
      [note] = notes(site, page)

      assert note_time(view, note) == "now"

      MishkaCmsBuilder.Repo.query!(
        "UPDATE page_comments SET inserted_at = inserted_at - interval '5 minutes' WHERE id = $1",
        [Ecto.UUID.dump!(note.id)]
      )

      send(view.pid, :review_clock)
      render_async(view)

      assert note_time(view, note) == "5m ago"
    end

    test "a minute with the sheet shut draws nothing", %{
      conn: conn,
      page: page
    } do
      {:ok, view, _html} = open_builder(conn, page)

      send(view.pid, :review_clock)
      render(view)

      assert live_assigns(view).review_clock == 0
    end

    defp note_time(view, note) do
      [_avatar, _name, time | _rest] =
        view
        |> element("#pb-comment-#{note.id} > div:first-child")
        |> render()
        |> LazyHTML.from_fragment()
        |> LazyHTML.query("span")
        |> Enum.map(&(&1 |> LazyHTML.text() |> String.trim()))

      time
    end
  end

  describe "the @ list" do
    test "offers the people on this page first and never the writer", %{
      conn: conn,
      page: page,
      site: site
    } do
      # Addresses that sort before everyone involved, so alphabetical order alone would show them.
      for n <- 1..6, do: create_admin("aaa.bystander#{n}@example.com")

      {_author, author_conn} = signed_in("zz.author@example.com")
      _note = heading_note!(author_conn, page, site, "An earlier note")

      # boss@example.com is editing; the writer joins their session.
      {:ok, first, _html} = open_builder(conn, page)
      {_writer, writer_conn} = signed_in("zzz.writer@example.com")

      {:ok, view, _html} =
        live(
          writer_conn,
          "/admin/dashboard/runtime/builder/page/#{page.id}?session=#{token(first)}"
        )

      render_click(view, "open_sheet", %{"sheet" => "review"})
      render_hook(view, "mention_search", %{"q" => ""})

      offered = Enum.map(live_assigns(view).mentions, & &1.handle)

      assert Enum.take(offered, 2) == ["boss@example.com", "zz.author@example.com"]
      refute "zzz.writer@example.com" in offered, "naming yourself notifies nobody"
      assert length(offered) == 6
    end
  end

  describe "the avatar stack" do
    # Two masters whose addresses share a first letter both read "M"; the chip has to say who.
    test "two people with one set of initials wear different colours and their own names", %{
      conn: conn,
      page: page
    } do
      {:ok, first, _html} = open_builder(conn, page)
      shared = token(first)
      {_twin, twin_conn} = signed_in("bob@example.com")

      {:ok, second, _html} =
        live(twin_conn, "/admin/dashboard/runtime/builder/page/#{page.id}?session=#{shared}")

      render(first)
      chips = stack(first)

      assert Enum.map(chips, & &1.initials) == ["B", "B"]
      assert Enum.map(chips, & &1.label) == ["boss@example.com (you)", "bob@example.com"]
      assert Enum.map(chips, & &1.title) == Enum.map(chips, & &1.label)

      assert Enum.uniq_by(chips, & &1.colour) == chips,
             "two people, one colour: #{inspect(chips)}"

      # Each side names the other, and the presence entries still carry no address.
      assert Enum.map(stack(second), & &1.label) == ["bob@example.com (you)", "boss@example.com"]
      refute Presence.editors(shared) |> inspect() =~ "@"
    end

    test "a site user is shown a master as Master", %{conn: conn, page: page, site: site} do
      {:ok, first, _html} = open_builder(conn, page)
      joiner = create_admin("tenant.side@example.com", site.id)

      {:ok, second, _html} =
        live(
          log_in(build_conn_for_host(), joiner),
          "/admin/dashboard/runtime/builder/page/#{page.id}?session=#{token(first)}"
        )

      assert Enum.map(stack(second), & &1.label) == ["tenant.side@example.com (you)", "Master"]
    end

    # Below 1180px the stack is hidden; a colleague in the session must not vanish with it.
    test "a narrow bar still counts who is here, and says nothing when you are alone", %{
      conn: conn,
      page: page
    } do
      {:ok, first, _html} = open_builder(conn, page)
      refute has_element?(first, "#pb-editors-count")

      {_colleague, colleague_conn} = signed_in("narrow.colleague@example.com")

      {:ok, _second, _html} =
        live(
          colleague_conn,
          "/admin/dashboard/runtime/builder/page/#{page.id}?session=#{token(first)}"
        )

      render(first)
      count = first |> element("#pb-editors-count") |> render()

      assert count =~ "max-[1180px]:flex"
      assert count =~ "max-[560px]:hidden", "a phone's bar is already cut off at its right end"
      assert count =~ ~r/>\s*2\s*</
      assert count =~ "boss@example.com (you), narrow.colleague@example.com"
    end

    defp stack(view) do
      view
      |> element("#pb-avatars")
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#pb-avatars > span")
      |> Enum.map(fn chip ->
        class = chip |> LazyHTML.attribute("class") |> Enum.join(" ")

        %{
          initials: chip |> LazyHTML.text() |> String.trim(),
          label: chip |> LazyHTML.attribute("aria-label") |> List.first(),
          title: chip |> LazyHTML.attribute("title") |> List.first(),
          colour: Regex.run(~r/\[background:(#[0-9a-f]{6})\]/, class, capture: :all_but_first)
        }
      end)
    end
  end
end
