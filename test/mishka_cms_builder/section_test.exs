# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.SectionTest do
  @moduledoc """
  The builder's own spelling of what it edits agrees with core's `Section`.

  The same fact was once written in ten places in two spellings, and the two lists only met when the
  editor tried to open an error page. `MishkaCmsCore.Runtime.Authoring.Section` is the one owner;
  the sections the history files an entry under have to be exactly its names.
  """
  use ExUnit.Case, async: true

  alias MishkaCmsCore.Runtime.Authoring.Section

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
