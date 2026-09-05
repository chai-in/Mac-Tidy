//go:build darwin

package main

import "testing"

func TestRunTrashJSONModeRequiresNativeConfirmation(t *testing.T) {
	t.Setenv("MOLE_GUI_CONFIRMED", "")
	if err := runTrashJSONMode([]string{"/"}); err == nil {
		t.Fatal("expected unconfirmed mutation to be rejected")
	}
}

func TestRunTrashJSONModeRejectsEmptySelection(t *testing.T) {
	t.Setenv("MOLE_GUI_CONFIRMED", "1")
	if err := runTrashJSONMode(nil); err == nil {
		t.Fatal("expected empty selection to be rejected")
	}
}

func TestTrashPathsForGUIDeduplicatesAndKeepsProtection(t *testing.T) {
	results, failed := trashPathsForGUI([]string{"/", "/"})
	if !failed {
		t.Fatal("expected protected root to fail")
	}
	if len(results) != 1 {
		t.Fatalf("expected duplicate path to be processed once, got %d", len(results))
	}
	if results[0].Status != "failed" {
		t.Fatalf("expected failed status, got %q", results[0].Status)
	}
}
