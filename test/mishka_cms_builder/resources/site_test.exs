# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.Resources.SiteTest do
  @moduledoc """
  The editor's helpers keep no AST built from a site's builder resources and no cache for it. The
  raw read that fed them is refused on the Site resource itself (core's `Resources.SiteTest`).
  """
  use ExUnit.Case, async: false

  @moduletag :unit

  # NO READ OF ANY SITE'S BUILDER RESOURCES BY AN ID IN INPUT. The raw action took a `site_id` and
  # answered that site's row, components and layouts to anybody holding a dashboard permission,
  # whatever their own site; nothing called it. The builder reads its palette through
  # `:for_tenant_with_globals`, which decides the site from who is asking.
  describe "no raw read of a site's builder resources" do
    # What that read fed: an AST built from every row it returned, each page wrapped in whatever
    # layout its id named, and a cache for it. Nothing calls either.
    test "nor the AST it was encoded into, nor the cache that held it" do
      refute Keyword.has_key?(MishkaCmsBuilder.Helpers.__info__(:functions), :builder_encoded_ast)
      refute Code.ensure_loaded?(MishkaCmsCore.Runtime.States.PageBuilderAstState)
    end
  end
end
