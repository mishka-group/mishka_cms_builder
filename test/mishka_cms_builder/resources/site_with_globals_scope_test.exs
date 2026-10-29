# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Resources.SiteWithGlobalsScopeTest do
  @moduledoc """
  The reads that answer "this site's rows plus the shared ones" — `:for_tenant_with_globals` and its
  single-row twin, the builder's `:for_editor` reads, a stylesheet's `:for_compiler` and a setting's
  own — decide whose rows they show from WHO IS ASKING, never from a missing tenant.

  A master is a user whose `site_id` is nil. A site user, whatever it holds, reads its own site and
  the shared rows and nothing else: not with no tenant, not by naming another site in `site_id`, not
  by passing another site's tenant. A call made as the system (`authorize?: false`, no actor) keeps
  the master's reach; a call made as nobody reads nothing.
  """
  use MishkaCmsCore.DataCase, async: false

  import MishkaCmsCore.Test.Factory

  alias MishkaCmsCore.Runtime.Component
  alias MishkaCmsCore.Runtime.JsHook
  alias MishkaCmsCore.Runtime.Layout
  alias MishkaCmsBuilder.PageComment
  alias MishkaCmsBuilder.Snippet
  alias MishkaCmsCore.Runtime.Stylesheet

  @moduletag :unit

  setup do
    site_a = create_site!()
    site_b = create_site!()

    %{
      site_a: site_a,
      site_b: site_b,
      star_a: create_user_with_permissions!(["*"], site_id: site_a.id),
      master: create_user_with_permissions!(["*"])
    }
  end

  defp ids(resource, action, args, build_opts, read_opts) do
    resource
    |> Ash.Query.for_read(action, args, build_opts)
    |> Ash.read(read_opts)
    |> case do
      {:ok, %{results: rows}} -> MapSet.new(rows, & &1.id)
      {:ok, rows} when is_list(rows) -> MapSet.new(rows, & &1.id)
      {:error, _refused} -> MapSet.new()
    end
  end

  describe "the builder's :for_editor reads" do
    setup context do
      page_b = create_page!(site_id: context.site_b.id)

      note =
        PageComment
        |> Ash.Changeset.for_create(
          :create,
          %{body: "site B's note", type: :information, section: :page, document_id: page_b.id},
          tenant: context.site_b.id,
          authorize?: false
        )
        |> Ash.create!()

      snippet =
        Snippet
        |> Ash.Changeset.for_create(
          :master_create,
          %{
            name: "site-b-snippet",
            source: "<p>site B</p>",
            section: :page,
            scope: :shared,
            site_id: context.site_b.id
          },
          authorize?: false
        )
        |> Ash.create!()

      %{page_b: page_b, note: note, snippet: snippet}
    end

    test "a site user reads no note of another site, by site_id or by tenant", context do
      args = %{site_id: context.site_b.id, section: :page, document_id: context.page_b.id}

      by_argument =
        ids(PageComment, :for_editor, args, [actor: context.star_a], actor: context.star_a)

      by_tenant =
        ids(
          PageComment,
          :for_editor,
          args,
          [actor: context.star_a, tenant: context.site_b.id],
          actor: context.star_a
        )

      refute MapSet.member?(by_argument, context.note.id)
      refute MapSet.member?(by_tenant, context.note.id)
    end

    test "nor through the system read the builder's own thread list makes", context do
      read =
        ids(
          PageComment,
          :for_editor,
          %{site_id: context.site_b.id, section: :page, document_id: context.page_b.id},
          [actor: context.star_a, authorize?: false],
          actor: context.star_a,
          authorize?: false
        )

      refute MapSet.member?(read, context.note.id)
    end

    test "a site user reads no snippet of another site", context do
      read =
        ids(
          Snippet,
          :for_editor,
          %{site_id: context.site_b.id, section: :page},
          [actor: context.star_a],
          actor: context.star_a
        )

      refute MapSet.member?(read, context.snippet.id)
    end

    test "a master reads another site's note and snippet by naming the site", context do
      notes =
        ids(
          PageComment,
          :for_editor,
          %{site_id: context.site_b.id, section: :page, document_id: context.page_b.id},
          [actor: context.master],
          actor: context.master
        )

      snippets =
        ids(
          Snippet,
          :for_editor,
          %{site_id: context.site_b.id, section: :page},
          [actor: context.master],
          actor: context.master
        )

      assert MapSet.member?(notes, context.note.id)
      assert MapSet.member?(snippets, context.snippet.id)
    end
  end
end
