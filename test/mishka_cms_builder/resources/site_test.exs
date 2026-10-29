# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Resources.SiteTest do
  @moduledoc """
  Comprehensive tests for Site resource.

  Site is the tenant entity in the multi-tenant architecture.
  Most actions are master-only except read/get which allow tenant users to see their own site.
  """
  use MishkaCmsCore.DataCase

  use ExUnit.Case, async: false
  import Ash.Test
  require Ash.Query
  @moduletag :unit

  # NO READ OF ANY SITE'S BUILDER RESOURCES BY AN ID IN INPUT. The raw action took a `site_id` and
  # answered that site's row, components and layouts to anybody holding a dashboard permission,
  # whatever their own site; nothing called it. The builder reads its palette through
  # `:for_tenant_with_globals`, which decides the site from who is asking.
  describe "no raw read of a site's builder resources" do
    # What that read fed: an AST built from every row it returned, each page wrapped in whatever
    # layout its id named, and a cache for it. Nothing calls either.
    test "nor the AST it was encoded into, nor the cache that held it" do
      Code.ensure_loaded!(MishkaCmsBuilder.Helpers)

      for arity <- [2, 3] do
        refute function_exported?(
                 MishkaCmsBuilder.Helpers,
                 :builder_encoded_ast,
                 arity
               )
      end

      refute Code.ensure_loaded?(MishkaCmsCore.Runtime.States.PageBuilderAstState)
    end
  end
end
