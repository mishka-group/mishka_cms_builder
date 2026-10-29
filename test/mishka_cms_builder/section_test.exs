# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.SectionTest do
  @moduledoc """
  The one owner of what the builder edits, and of the three ways each of them is spelled.

  This exists because the same fact was written in ten places in two spellings. The address says
  `error-page`, everything durable says `error_page`, and the difference was converted by hand in
  nine places across five modules — three of them a bare `String.to_existing_atom/1`, which is not a
  conversion but a crash waiting for the one section whose spellings differ. It took the builder's
  mount down for error pages, and the editor would not open there at all.
  """
  use ExUnit.Case, async: true

  alias MishkaCmsCore.Runtime.PageBuilder.Section

  @moduletag :unit

  describe "what the log files a section under" do
    test "agrees with what the builder calls it" do
      # The two lists were maintained separately, in different spellings, and only met when the
      # editor tried to open an error page.
      assert Enum.sort(Section.atoms()) ==
               Enum.sort(MishkaCmsBuilder.HistoryEvent.sources())
    end
  end
end
