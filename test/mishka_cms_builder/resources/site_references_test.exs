# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Resources.SiteReferencesTest do
  @moduledoc """
  Which records a site's record may name by id.

  One rule across every runtime resource that points at another site-owned record: a page's layout,
  a draft's layout and its live record, a media file's category. The record named belongs to the
  same site, or — where the target can be shared — to no site. Whoever writes, the system included:
  a page wrapped in another site's layout shows that site's template on this one.
  """
  use MishkaCmsCore.DataCase, async: false

  import MishkaCmsCore.Test.Factory

  require Ash.Query

  alias MishkaCmsCore.Runtime.{Page, PageDraft}

  @moduletag :unit

  setup do
    site = create_site!()
    other = create_site!()
    star = create_user_with_permissions!(["*"], site_id: site.id)

    %{site: site, other: other, star: star}
  end

  defp unique, do: System.unique_integer([:positive])

  defp master!, do: create_user_with_permissions!(["*"])

  defp page_draft!(site_id) do
    n = unique()

    PageDraft
    |> Ash.Changeset.for_create(
      :create,
      %{name: "Draft #{n}", title: "Draft #{n}", path: "/draft-#{n}", template: "<div></div>"},
      tenant: site_id,
      authorize?: false
    )
    |> Ash.create!(authorize?: false)
  end

  describe "an id whose kind another field names" do
    alias MishkaCmsCore.Runtime.Component
    alias MishkaCmsCore.Runtime.ErrorPage
    alias MishkaCmsCore.Runtime.Layout
    alias MishkaCmsBuilder.PageComment
    alias MishkaCmsCore.Runtime.Resources.Validations.SameSiteReference

    defp kinds_opts do
      {:ok, opts} =
        SameSiteReference.init(
          field: :document_id,
          resource:
            {:section, %{page: Page, layout: Layout, error_page: ErrorPage, component: Component}},
          label: "document",
          shared?: true
        )

      opts
    end

    defp check_kind(changeset), do: SameSiteReference.validate(changeset, kinds_opts(), %{})

    defp note(attrs) do
      PageComment
      |> Ash.Changeset.new()
      |> Ash.Changeset.force_change_attributes(attrs)
    end

    test "names a record of the kind that field picks, on the same site", context do
      page = create_page!(site_id: context.site.id)
      layout = create_layout!(site_id: context.site.id)

      assert :ok =
               check_kind(note(%{site_id: context.site.id, section: :page, document_id: page.id}))

      assert :ok =
               check_kind(
                 note(%{site_id: context.site.id, section: :layout, document_id: layout.id})
               )
    end

    test "never another site's record of that kind", context do
      theirs = create_page!(site_id: context.other.id)

      assert {:error, error} =
               check_kind(
                 note(%{site_id: context.site.id, section: :page, document_id: theirs.id})
               )

      assert error[:message] == "That document is not one this site can use."
    end

    test "never a record of another kind than the one named", context do
      layout = create_layout!(site_id: context.site.id)

      assert {:error, _refused} =
               check_kind(
                 note(%{site_id: context.site.id, section: :page, document_id: layout.id})
               )
    end

    test "a shared record of that kind where shared records are allowed", context do
      shared = create_component!(site_id: nil)

      assert :ok =
               check_kind(
                 note(%{site_id: context.site.id, section: :component, document_id: shared.id})
               )
    end

    test "a kind the map does not hold is refused", context do
      page = create_page!(site_id: context.site.id)

      {:ok, opts} =
        SameSiteReference.init(
          field: :document_id,
          resource: {:section, %{layout: Layout}},
          label: "document"
        )

      assert {:error, _refused} =
               SameSiteReference.validate(
                 note(%{site_id: context.site.id, section: :page, document_id: page.id}),
                 opts,
                 %{}
               )
    end

    test "is checked again when only the kind changes", context do
      page = create_page!(site_id: context.site.id)

      existing = %PageComment{site_id: context.site.id, section: :page, document_id: page.id}

      assert {:error, _refused} =
               existing
               |> Ash.Changeset.new()
               |> Ash.Changeset.force_change_attribute(:section, :layout)
               |> check_kind()
    end
  end

  describe "a user named by a site's record" do
    alias MishkaCmsCore.Accounts.User
    alias MishkaCmsBuilder.PageComment
    alias MishkaCmsCore.Runtime.Resources.Validations.SameSiteReference

    defp check_user(site_id, user_id, extra_opts \\ [shared?: true]) do
      {:ok, opts} =
        SameSiteReference.init(
          [field: :author_id, resource: User, label: "author", read_action: :related] ++
            extra_opts
        )

      PageComment
      |> Ash.Changeset.new()
      |> Ash.Changeset.force_change_attributes(%{site_id: site_id, author_id: user_id})
      |> SameSiteReference.validate(opts, %{})
    end

    test "is one of that site's accounts", context do
      assert :ok = check_user(context.site.id, create_user!(site_id: context.site.id).id)
    end

    test "or a master, who acts on every site", context do
      master = create_user!(site_id: nil)

      assert :ok = check_user(context.site.id, master.id)
      assert {:error, _refused} = check_user(context.site.id, master.id, [])
    end

    test "never another site's account", context do
      theirs = create_user!(site_id: context.other.id)

      assert {:error, error} = check_user(context.site.id, theirs.id)
      assert error[:message] == "That author is not one this site can use."
    end

    test "a record with no site names only a master", context do
      assert {:error, _refused} =
               check_user(nil, create_user!(site_id: context.site.id).id)

      assert :ok = check_user(nil, create_user!(site_id: nil).id)
    end
  end

  describe "the site a record is judged by" do
    alias MishkaCmsBuilder.{HistoryEvent, PageComment, Snippet}

    defp history_row(tenant, attrs, actor, authorize?) do
      HistoryEvent
      |> Ash.Changeset.for_create(
        :create,
        Map.merge(
          %{
            id: Ecto.UUID.generate(),
            source_type: :page,
            label: "Set gap (base)",
            kind: :style,
            op: :set_style
          },
          attrs
        ),
        tenant: tenant,
        actor: actor,
        authorize?: authorize?
      )
      |> Ash.create(actor: actor, authorize?: authorize?)
    end

    defp system_master_create(resource, attrs, tenant) do
      resource
      |> Ash.Changeset.for_create(:master_create, attrs, tenant: tenant, authorize?: false)
      |> Ash.create(authorize?: false)
    end

    test "is the tenant a create stores, not a site_id in its input", context do
      theirs = create_page!(site_id: context.other.id)
      own = create_page!(site_id: context.site.id)

      for {actor, authorize?} <- [{master!(), true}, {nil, false}] do
        assert {:error, error} =
                 history_row(
                   context.site.id,
                   %{site_id: context.other.id, source_id: theirs.id},
                   actor,
                   authorize?
                 )

        assert Exception.message(error) =~ "document is not one this site can use"

        assert {:ok, row} =
                 history_row(
                   context.site.id,
                   %{site_id: context.other.id, source_id: own.id},
                   actor,
                   authorize?
                 )

        assert row.site_id == context.site.id
      end
    end

    test "is none for a master's create that stores the row shared, whatever the tenant",
         context do
      page = create_page!(site_id: context.site.id)
      component = create_component!(site_id: context.site.id)
      shared = create_component!(site_id: nil)
      snippet = %{name: "Hero #{unique()}", source: "<div>hero</div>", section: :page}
      note = %{body: "Check this", type: :bug, section: :component}

      assert {:error, error} =
               system_master_create(
                 Snippet,
                 Map.put(snippet, :document_id, page.id),
                 context.site.id
               )

      assert Exception.message(error) =~ "document is not one this site can use"

      assert {:error, error} =
               system_master_create(
                 PageComment,
                 Map.put(note, :document_id, component.id),
                 context.site.id
               )

      assert Exception.message(error) =~ "document is not one this site can use"

      assert {:ok, %{site_id: nil}} =
               system_master_create(
                 PageComment,
                 Map.put(note, :document_id, shared.id),
                 context.site.id
               )
    end
  end

  describe "a builder history row" do
    alias MishkaCmsBuilder.HistoryEvent

    defp event(context, attrs, actor, opts \\ []) do
      attrs =
        Map.merge(
          %{
            id: Ecto.UUID.generate(),
            source_type: :page,
            site_id: context.site.id,
            label: "Set gap (base)",
            kind: :style,
            op: :set_style
          },
          attrs
        )

      authorize? = Keyword.get(opts, :authorize?, true)

      HistoryEvent
      |> Ash.Changeset.for_create(:create, attrs,
        tenant: context.site.id,
        actor: actor,
        authorize?: authorize?
      )
      |> Ash.create(actor: actor, authorize?: authorize?)
    end

    test "names no document of another site, whoever writes", context do
      theirs = create_page!(site_id: context.other.id)

      for actor <- [context.star, master!()] do
        assert {:error, error} = event(context, %{source_id: theirs.id}, actor)
        assert Exception.message(error) =~ "document is not one this site can use"
      end

      assert {:error, _refused} =
               event(context, %{source_id: theirs.id}, nil, authorize?: false)
    end

    test "nor another site's draft", context do
      page = create_page!(site_id: context.site.id)
      theirs = page_draft!(context.other.id)

      for actor <- [context.star, master!()] do
        assert {:error, error} =
                 event(context, %{source_id: page.id, draft_id: theirs.id}, actor)

        assert Exception.message(error) =~ "draft is not one this site can use"
      end
    end

    test "nor an author of another site", context do
      page = create_page!(site_id: context.site.id)
      stranger = create_user!(site_id: context.other.id)

      assert {:error, error} =
               event(context, %{source_id: page.id}, stranger, authorize?: false)

      assert Exception.message(error) =~ "author is not one this site can use"
    end

    test "names its own site's document and draft, or a shared one", context do
      page = create_page!(site_id: context.site.id)
      draft = page_draft!(context.site.id)
      shared = create_layout!(site_id: nil)

      for actor <- [context.star, master!()] do
        assert {:ok, _row} = event(context, %{source_id: page.id, draft_id: draft.id}, actor)

        assert {:ok, _row} =
                 event(context, %{source_type: :layout, source_id: shared.id}, actor)
      end
    end

    test "a draft adopted later is the row's own site's too", context do
      page = create_page!(site_id: context.site.id)
      {:ok, row} = event(context, %{source_id: page.id}, context.star)

      adopt = fn draft ->
        row
        |> Ash.Changeset.for_update(:adopt_draft, %{draft_id: draft.id},
          tenant: context.site.id,
          actor: context.star
        )
        |> Ash.update(actor: context.star)
      end

      assert {:error, _refused} = adopt.(page_draft!(context.other.id))
      assert {:ok, %{draft_id: _adopted}} = adopt.(page_draft!(context.site.id))
    end

    test "a note is signed by an account of the row's site or a master", context do
      page = create_page!(site_id: context.site.id)
      {:ok, row} = event(context, %{source_id: page.id}, context.star)

      annotate = fn actor ->
        row
        |> Ash.Changeset.for_update(:annotate, %{note: "Deliberate."},
          actor: actor,
          authorize?: false
        )
        |> Ash.update(actor: actor, authorize?: false)
      end

      assert {:error, _refused} = annotate.(create_user!(site_id: context.other.id))
      assert {:ok, %{note: "Deliberate."}} = annotate.(context.star)
      assert {:ok, %{note: "Deliberate."}} = annotate.(master!())
    end
  end

  describe "a review note" do
    alias MishkaCmsBuilder.PageComment

    defp note_as(actor, tenant, attrs) do
      action = if actor.site_id, do: :create, else: :master_create

      PageComment
      |> Ash.Changeset.for_create(
        action,
        Map.merge(%{body: "Check this", type: :bug}, attrs),
        actor: actor,
        tenant: tenant
      )
      |> Ash.create(actor: actor)
    end

    test "is about no document of another site, whoever writes", context do
      theirs = create_page!(site_id: context.other.id)
      attrs = %{section: :page, document_id: theirs.id}

      assert {:error, error} = note_as(context.star, context.site.id, attrs)
      assert Exception.message(error) =~ "document is not one this site can use"

      assert {:error, error} =
               note_as(master!(), nil, Map.put(attrs, :site_id, context.site.id))

      assert Exception.message(error) =~ "document is not one this site can use"
    end

    test "is about its own site's document or a shared one", context do
      page = create_page!(site_id: context.site.id)
      shared = create_component!(site_id: nil)

      for {actor, tenant, extra} <- [
            {context.star, context.site.id, %{}},
            {master!(), nil, %{site_id: context.site.id}}
          ] do
        assert {:ok, _note} =
                 note_as(actor, tenant, Map.merge(extra, %{section: :page, document_id: page.id}))

        assert {:ok, _note} =
                 note_as(
                   actor,
                   tenant,
                   Map.merge(extra, %{section: :component, document_id: shared.id})
                 )
      end
    end

    test "a note with no site is about a shared document only", context do
      theirs = create_layout!(site_id: context.site.id)

      assert {:error, _refused} =
               note_as(master!(), nil, %{section: :layout, document_id: theirs.id})
    end

    test "answers no note of another site", context do
      shared = create_component!(site_id: nil)
      on_shared = %{section: :component, document_id: shared.id}
      other_star = create_user_with_permissions!(["*"], site_id: context.other.id)

      {:ok, theirs} = note_as(other_star, context.other.id, on_shared)
      reply = Map.put(on_shared, :parent_comment_id, theirs.id)

      assert {:error, error} = note_as(context.star, context.site.id, reply)
      assert Exception.message(error) =~ "note is not one this site can use"

      assert {:error, _refused} =
               note_as(master!(), nil, Map.put(reply, :site_id, context.site.id))
    end

    test "answers its own site's note or a shared one", context do
      shared = create_component!(site_id: nil)
      on_shared = %{section: :component, document_id: shared.id}

      {:ok, own} = note_as(context.star, context.site.id, on_shared)
      {:ok, global} = note_as(master!(), nil, on_shared)

      for parent <- [own, global] do
        assert {:ok, _reply} =
                 note_as(
                   context.star,
                   context.site.id,
                   Map.put(on_shared, :parent_comment_id, parent.id)
                 )
      end
    end

    test "names no author of another site", context do
      page = create_page!(site_id: context.site.id)
      attrs = %{site_id: context.site.id, section: :page, document_id: page.id}

      assert {:error, error} =
               note_as(
                 master!(),
                 nil,
                 Map.put(attrs, :author_id, create_user!(site_id: context.other.id).id)
               )

      assert Exception.message(error) =~ "author is not one this site can use"

      assert {:error, _refused} =
               PageComment
               |> Ash.Changeset.for_create(
                 :create,
                 %{body: "Check this", type: :bug, section: :page, document_id: page.id},
                 actor: create_user!(site_id: context.other.id),
                 tenant: context.site.id,
                 authorize?: false
               )
               |> Ash.create(authorize?: false)

      assert {:ok, _note} =
               note_as(master!(), nil, Map.put(attrs, :author_id, master!().id))
    end

    test "is resolved by an account of its site or a master", context do
      page = create_page!(site_id: context.site.id)

      {:ok, note} =
        note_as(context.star, context.site.id, %{section: :page, document_id: page.id})

      resolve = fn action, actor ->
        note
        |> Ash.Changeset.for_update(action, %{},
          actor: actor,
          tenant: context.site.id,
          authorize?: false
        )
        |> Ash.update(authorize?: false)
      end

      for action <- [:resolve, :master_resolve] do
        assert {:error, error} = resolve.(action, create_user!(site_id: context.other.id))
        assert Exception.message(error) =~ "resolver is not one this site can use"
      end

      assert {:ok, %{status: :resolved}} = resolve.(:resolve, context.star)
      assert {:ok, %{status: :resolved}} = resolve.(:master_resolve, master!())
    end
  end

  describe "a saved snippet" do
    alias MishkaCmsBuilder.Snippet

    defp snippet_as(actor, tenant, attrs) do
      action = if actor.site_id, do: :create, else: :master_create

      Snippet
      |> Ash.Changeset.for_create(
        action,
        Map.merge(%{name: "Hero #{unique()}", source: "<div>hero</div>", section: :page}, attrs),
        actor: actor,
        tenant: tenant
      )
      |> Ash.create(actor: actor)
    end

    test "names no document of another site, whoever writes", context do
      theirs = create_page!(site_id: context.other.id)
      attrs = %{scope: :page, document_id: theirs.id}

      assert {:error, error} = snippet_as(context.star, context.site.id, attrs)
      assert Exception.message(error) =~ "document is not one this site can use"

      assert {:error, _refused} =
               snippet_as(master!(), nil, Map.put(attrs, :site_id, context.site.id))
    end

    test "names its own site's document or a shared one", context do
      page = create_page!(site_id: context.site.id)
      shared = create_layout!(site_id: nil)

      for {actor, tenant, extra} <- [
            {context.star, context.site.id, %{}},
            {master!(), nil, %{site_id: context.site.id}}
          ] do
        assert {:ok, _snippet} =
                 snippet_as(
                   actor,
                   tenant,
                   Map.merge(extra, %{scope: :page, document_id: page.id})
                 )

        assert {:ok, _snippet} =
                 snippet_as(
                   actor,
                   tenant,
                   Map.merge(extra, %{section: :layout, document_id: shared.id})
                 )
      end
    end

    test "one for every site names only a shared document", context do
      page = create_page!(site_id: context.site.id)
      shared = create_layout!(site_id: nil)

      assert {:error, _refused} = snippet_as(master!(), nil, %{document_id: page.id})

      assert {:ok, _snippet} =
               snippet_as(master!(), nil, %{section: :layout, document_id: shared.id})
    end

    test "the Studio saves one for every site without the site's document", context do
      page_id = create_page!(site_id: context.site.id).id

      state =
        &%{
          master_user?: true,
          defaults: %{section: :page, editor_document_id: page_id, editor_site_id: &1}
        }

      assert %{"site_id" => nil, "document_id" => nil} =
               Snippet.apply_visibility(%{"visibility" => "global"}, state.(context.site.id))

      assert %{"site_id" => site_id, "document_id" => ^page_id} =
               Snippet.apply_visibility(%{"visibility" => "shared"}, state.(context.site.id))

      assert site_id == context.site.id

      assert %{"site_id" => nil, "document_id" => ^page_id} =
               Snippet.apply_visibility(%{"visibility" => "global"}, state.(nil))
    end
  end

  describe "a record other records name, moved to another site" do
    alias MishkaCmsCore.Accounts.User
    alias MishkaCmsCore.Runtime.Component
    alias MishkaCmsCore.Runtime.Layout
    alias MishkaCmsBuilder.PageComment
    alias MishkaCmsCore.Runtime.Resources.Validations.SameSiteReference

    @moved_away "still use this"

    defp move(record, site_id, master) do
      record.__struct__
      |> Ash.get!(record.id, action: :get_any, authorize?: false)
      |> Ash.Changeset.for_update(:master_update, %{site_id: site_id}, actor: master)
      |> Ash.update(actor: master)
    end

    defp move_account(user, site_id, master) do
      User
      |> Ash.ActionInput.for_action(:master_update, %{id: user.id, site_id: site_id},
        actor: master
      )
      |> Ash.run_action(actor: master)
    end

    defp move_account_by_form(user, site_id, master) do
      User
      |> Ash.get!(user.id, action: :master_get, authorize?: false)
      |> Ash.Changeset.for_update(:master_form_update, %{site_id: site_id}, actor: master)
      |> Ash.update(actor: master)
    end

    defp site_of(record),
      do: Ash.get!(record.__struct__, record.id, action: :get_any, authorize?: false).site_id

    defp account_site(user),
      do: Ash.get!(User, user.id, action: :master_get, authorize?: false).site_id

    defp note_by(author, attrs) do
      PageComment
      |> Ash.Changeset.for_create(:create, Map.merge(%{body: "Check this", type: :bug}, attrs),
        actor: author,
        tenant: author.site_id
      )
      |> Ash.create!(actor: author)
    end

    test "a layout a shared record names stays shared", context do
      master = master!()
      shared = create_layout!(site_id: nil)

      {:ok, _note} =
        PageComment
        |> Ash.Changeset.for_create(
          :master_create,
          %{body: "Check this", type: :bug, section: :layout, document_id: shared.id},
          actor: master
        )
        |> Ash.create(actor: master)

      assert {:error, _refused} = move(shared, context.site.id, master)
      assert site_of(shared) == nil
    end

    test "a component a site's note is about stays on that site, or becomes shared", context do
      master = master!()
      component = create_component!(site_id: context.site.id)
      note_by(context.star, %{section: :component, document_id: component.id})

      assert {:error, error} = move(component, context.other.id, master)
      assert Exception.message(error) =~ "Records outside that site #{@moved_away} component"
      assert site_of(component) == context.site.id

      assert {:ok, %{site_id: nil}} = move(component, nil, master)
    end

    test "an account its site's records name stays on that site, or becomes a master",
         context do
      master = master!()
      author = create_user_with_permissions!(["*"], site_id: context.site.id)
      note_by(author, %{section: :page, document_id: create_page!(site_id: context.site.id).id})

      assert {:error, error} = move_account(author, context.other.id, master)
      assert Exception.message(error) =~ "Records outside that site #{@moved_away} account"

      assert {:error, _refused} = move_account_by_form(author, context.other.id, master)
      assert account_site(author) == context.site.id

      assert {:ok, %{site_id: nil}} = move_account(author, nil, master)
    end
  end
end
