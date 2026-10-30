# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Resources.SiteWithGlobalsPolicyTest do
  @moduledoc """
  Every read of the editor's own records that scopes by who built it is held, when it runs, by a
  policy on the actor's own site.

  `MishkaCmsCore.Runtime.Resources.Preparations.SiteWithGlobals` narrows a read to "this site's rows
  plus the shared ones" by the actor that built the query. A query built as the system, or as one
  actor and run as another, is scoped by the first, so the preparation alone is not the rule: a
  policy that asks the actor who runs it has to hold the read too.

  The core makes the same scan over the domains it configures. The editor's notes and snippets belong
  to `MishkaCmsBuilder`, a domain the core does not list, so this scan reads theirs.
  """
  use ExUnit.Case, async: true

  @moduletag :unit

  @preparation MishkaCmsCore.Runtime.Resources.Preparations.SiteWithGlobals

  defp site_with_globals?(%{preparation: {module, _opts}}), do: module == @preparation
  defp site_with_globals?(_preparation), do: false

  defp applies_to_reads?(%{condition: conditions}) do
    Enum.all?(conditions, fn
      {Ash.Policy.Check.ActionType, opts} -> :read in List.wrap(opts[:type])
      {Ash.Policy.Check.Static, opts} -> opts[:result] == true
      _other -> false
    end)
  end

  defp masters_only_by_identity?(%{policies: checks}) do
    Enum.any?(checks, fn
      %{
        type: :authorize_if,
        check_module: Ash.Policy.Check.ActorAttributeEquals,
        check_opts: opts
      } ->
        opts[:attribute] == :site_id and Keyword.has_key?(opts, :value) and is_nil(opts[:value])

      _other ->
        false
    end)
  end

  defp held_by_identity?(resource) do
    resource
    |> Ash.Policy.Info.policies()
    |> Enum.any?(&(applies_to_reads?(&1) and masters_only_by_identity?(&1)))
  end

  test "is held by a policy on the actor when it runs" do
    scoped =
      for resource <- Ash.Domain.Info.resources(MishkaCmsBuilder),
          action <- Ash.Resource.Info.actions(resource),
          action.type == :read,
          Enum.any?(action.preparations, &site_with_globals?/1),
          do: {resource, action.name}

    assert length(scoped) >= 2, "found #{length(scoped)}; the scan proves nothing"

    for {resource, action} <- scoped do
      assert held_by_identity?(resource),
             "#{inspect(resource)}.#{action} uses SiteWithGlobals with no read policy on the actor"
    end
  end
end
