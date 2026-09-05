//go:build darwin

package main

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type guiTrashResult struct {
	Path   string `json:"path"`
	Status string `json:"status"`
	Error  string `json:"error,omitempty"`
}

func runTrashJSONMode(paths []string) error {
	if os.Getenv("MOLE_GUI_CONFIRMED") != "1" {
		return fmt.Errorf("native-app confirmation is required before moving items to Trash")
	}
	if len(paths) == 0 {
		return fmt.Errorf("no paths selected")
	}
	results, failed := trashPathsForGUI(paths)
	if err := json.NewEncoder(os.Stdout).Encode(results); err != nil {
		fmt.Fprintf(os.Stderr, "failed to encode Trash results: %v\n", err)
		return err
	}
	if failed {
		return fmt.Errorf("one or more paths could not be moved to Trash")
	}
	return nil
}

// trashPathsForGUI enters the same moveToTrash funnel as the interactive
// analyzer. Paths are deduplicated and processed deepest-first so selecting a
// parent and child cannot make the child look like an unexplained failure.
func trashPathsForGUI(paths []string) ([]guiTrashResult, bool) {
	seen := make(map[string]struct{}, len(paths))
	ordered := make([]string, 0, len(paths))
	for _, path := range paths {
		if _, ok := seen[path]; ok {
			continue
		}
		seen[path] = struct{}{}
		ordered = append(ordered, path)
	}
	sort.SliceStable(ordered, func(i, j int) bool {
		return strings.Count(filepath.Clean(ordered[i]), string(filepath.Separator)) >
			strings.Count(filepath.Clean(ordered[j]), string(filepath.Separator))
	})

	results := make([]guiTrashResult, 0, len(ordered))
	failed := false
	for _, path := range ordered {
		result := guiTrashResult{Path: path, Status: "trashed"}
		if err := moveToTrash(path); err != nil {
			result.Status = "failed"
			result.Error = err.Error()
			failed = true
		}
		results = append(results, result)
	}
	return results, failed
}
