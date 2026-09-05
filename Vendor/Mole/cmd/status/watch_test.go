package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"testing"
)

func TestWatchSnapshotCarriesCollectionFailureAndClearsItOnRecovery(t *testing.T) {
	var output bytes.Buffer
	encoder := json.NewEncoder(&output)
	snapshot := MetricsSnapshot{HealthScore: 70}
	if err := encodeWatchSnapshot(encoder, snapshot, errors.New("disk query failed")); err != nil {
		t.Fatal(err)
	}
	snapshot.CollectionError = "stale failure"
	if err := encodeWatchSnapshot(encoder, snapshot, nil); err != nil {
		t.Fatal(err)
	}
	decoder := json.NewDecoder(&output)
	var failed, recovered MetricsSnapshot
	if err := decoder.Decode(&failed); err != nil {
		t.Fatal(err)
	}
	if err := decoder.Decode(&recovered); err != nil {
		t.Fatal(err)
	}
	if failed.CollectionError != "disk query failed" || recovered.CollectionError != "" {
		t.Fatalf("unexpected record errors: %q, %q", failed.CollectionError, recovered.CollectionError)
	}
	if recovered.HealthScore != 70 {
		t.Fatal("snapshot data changed while recording collection status")
	}
}
