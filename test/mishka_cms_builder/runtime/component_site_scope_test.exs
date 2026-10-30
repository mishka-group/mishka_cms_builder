# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Runtime.ComponentSiteScopeTest do
  @moduledoc """
  Whose components the editor's palette card draws: the site this process renders for, and the global
  ones.

  A component reads as its own site, so a template on one site that wrote
  `<.component component_name="…" site="another">` would draw that other site's markup to its own
  author. The core refuses such a name before building it (see the rest of this subject in its
  `component_site_scope_test.exs`); the palette's card renders through `MishkaCmsBuilder.CardPreview`,
  which must name the editor's site for as long as it renders and no longer. A test process names the
  site the way a page does, `MishkaCmsCore.Runtime.Translations.put_site/1`.

  `async: false` — `SiteState` and the event registry are process-global.
  """
  use MishkaCmsCore.DataCase, async: false

  alias MishkaCmsBuilder.CardPreview
  alias MishkaCmsCore.Runtime.Compilers.{Helpers, ModuleCompiler}
  alias MishkaCmsCore.Runtime.States.{CompileFailureState, SiteState}
  alias MishkaCmsCore.Runtime.Translations

  @moduletag :integration

  setup do
    %{home: site!("scope-home"), other: site!("scope-other")}
  end

  # AN ADMIN'S PROCESS PREVIEWS EVERY SITE'S RECORDS, one after another, so each preview names its
  # own site for as long as it renders and no longer. The test process starts out rendering for the
  # OTHER site, which is what a master's modal looks like after previewing that site's page first.
  describe "the admin's previews" do
    test "a palette card draws the editor's site's component and not another's", %{
      home: home,
      other: other
    } do
      own = component!(home, "card-own")
      foreign = component!(other, "card-foreign")
      :ok = Translations.put_site(other.id)

      {:ok, card} =
        CardPreview.document(
          ~s(<.component component_name="#{own.name}" site="#{home.name}" />),
          home.name
        )

      {:ok, stranger} =
        CardPreview.document(
          ~s(<.component component_name="#{foreign.name}" site="#{other.name}" />),
          home.name
        )

      assert card =~ "probe-card-own"
      refute stranger =~ "probe-card-foreign"
      assert Translations.site() == other.id
    end
  end

  defp site!(prefix), do: named_site!("#{prefix}-#{unique()}")

  defp named_site!(name) do
    site = create_site!(name: name, host: "#{name}.test")

    :ok =
      SiteState.save(%{id: site.id, name: site.name, host: site.host, priority: 0, active: true})

    on_exit(fn -> SiteState.delete(site.id) end)
    site
  end

  defp component!(site, tag, opts \\ []) do
    component =
      create_component!(
        Keyword.merge(
          [
            name: "scope-#{tag}-#{unique()}",
            template: ~s|<div class="probe-#{tag}">#{tag}</div>|,
            active: true,
            precompile: false,
            site_id: site && site.id
          ],
          opts
        )
      )

    module = module_for(component.name, site && site.name)

    on_exit(fn ->
      ModuleCompiler.unload(module)
      CompileFailureState.clear(module)
    end)

    component
  end

  defp module_for(name, site_name), do: Helpers.module_name(name, site_name, "Component")

  defp unique, do: System.unique_integer([:positive])
end
