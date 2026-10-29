# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Runtime.ComponentSiteScopeTest do
  @moduledoc """
  Whose components a render reaches: the site this process renders for, and the global ones.

  A component reads as its own site — the kits read `authorize?: false` with `tenant: site_id()` —
  so a template on one site that wrote `<.component component_name="…" site="another">` drew that
  other site's markup and rows to its own visitors, inactive or offline as that site might be, and
  ran its `handle_event` besides. `MishkaCmsCore.Runtime.LiveViewHelpers.component/1` now refuses
  such a name before building it, and so does `static_component/1`, which the canvas and the
  previews render through.

  The site being rendered is the one `MishkaCmsCore.Runtime.Translations.put_site/1` named for the
  process — see the surfaces that name it in `MishkaCmsCore.Runtime.LiveViewHelpers`. A test process
  names it the same way a page does.

  `async: false` — `SiteState` and the event registry are process-global.
  """
  use MishkaCmsCore.DataCase, async: false

  alias MishkaCmsCore.Runtime.Compilers.{Helpers, ModuleCompiler}
  alias MishkaCmsCore.Runtime.{Translations}
  alias MishkaCmsBuilder.CardPreview
  alias MishkaCmsCore.Runtime.States.{CompileFailureState, SiteState}

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
