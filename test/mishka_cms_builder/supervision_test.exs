# SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
#
# SPDX-License-Identifier: Apache-2.0

defmodule MishkaCmsBuilder.SupervisionTest do
  @moduledoc """
  What the builder starts itself. `MishkaCmsBuilder.Application` supervises the editor's processes
  (the open sessions, their history, the palette-card previews and the presence of the people in a
  session); neither the core's application nor the test harness starts them.
  """
  use ExUnit.Case, async: false

  describe "the editor's processes" do
    test "run under the builder's application" do
      ids = ids_of(MishkaCmsBuilder.Supervisor)

      for child <- [
            MishkaCmsBuilder.States.EditorSessionState,
            MishkaCmsBuilder.States.EditorHistoryState,
            MishkaCmsBuilder.States.CardPreviewState,
            MishkaCmsBuilder.Presence
          ] do
        assert child in ids, "#{inspect(child)} is not supervised by the builder's application"
      end
    end
  end

  defp ids_of(supervisor),
    do: for({id, _pid, _type, _modules} <- Supervisor.which_children(supervisor), do: id)
end
