package storage

import (
	"testing"
)

func TestParseGlusterPeerStatus(t *testing.T) {
	raw := `Number of Peers: 2

Hostname: 192.168.252.28
Uuid: b4c76b91-c247-4bc0-9c29-37397753eef6
State: Peer in Cluster (Connected)

Hostname: 192.168.252.29
Uuid: 994a5323-8cfb-4a57-be8e-a979207039a0
State: Peer in Cluster (Connected)
`
	peers := parseGlusterPeerStatus(raw)
	if len(peers) != 3 { // 1 local + 2 remote
		t.Fatalf("expected 3 peers, got %d", len(peers))
	}

	if peers[0].Hostname != "localhost (Manager)" || !peers[0].IsLocal {
		t.Errorf("expected first peer to be local manager, got %+v", peers[0])
	}

	if peers[1].Hostname != "192.168.252.28" || !peers[1].Connected {
		t.Errorf("expected peer 1 to be connected 192.168.252.28, got %+v", peers[1])
	}
}

func TestParseGlusterVolumeInfo(t *testing.T) {
	raw := `
Volume Name: gv_contenedores
Type: Replicate
Volume ID: 51b88e1a-c75c-4467-bc22-3c137452d7e2
Status: Started
Snapshot Count: 0
Number of Bricks: 1 x 3 = 3
Transport-type: tcp
Bricks:
Brick1: 192.168.252.27:/data/glusterfs/brick1/gv_contenedores
Brick2: 192.168.252.28:/data/glusterfs/brick1/gv_contenedores
Brick3: 192.168.252.29:/data/glusterfs/brick1/gv_contenedores
Options Reconfigured:
performance.write-behind: on
performance.flush-behind: on
network.ping-timeout: 10
`
	vols := parseGlusterVolumeInfo(raw)
	if len(vols) != 1 {
		t.Fatalf("expected 1 volume, got %d", len(vols))
	}

	v := vols[0]
	if v.Name != "gv_contenedores" {
		t.Errorf("expected name gv_contenedores, got %s", v.Name)
	}
	if v.Type != "Replicate" || v.ReplicaCount != 3 {
		t.Errorf("expected Replica 3, got type=%s, replica=%d", v.Type, v.ReplicaCount)
	}
	if len(v.Bricks) != 3 {
		t.Errorf("expected 3 bricks, got %d", len(v.Bricks))
	}
	if v.Options["performance.write-behind"] != "on" {
		t.Errorf("expected write-behind on, got %s", v.Options["performance.write-behind"])
	}
}

func TestGlusterDiagnostics(t *testing.T) {
	diag, err := GetGlusterDiagnostics()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if diag == nil {
		t.Fatal("expected non-nil diagnostics")
	}
	if diag.HealthScore < 0 || diag.HealthScore > 100 {
		t.Errorf("invalid health score: %d", diag.HealthScore)
	}
}

func TestCreateGlusterVolumeAutoBricks(t *testing.T) {
	setupTestDB(t)

	req := GlusterVolumeCreateRequest{
		Name:         "test_vol_2",
		ReplicaCount: 2,
		BrickDir:     "/data/glusterfs/brick2",
		MountPoint:   "/var/contenedores2",
		TargetNodes:  []string{"192.168.252.27", "192.168.252.25"},
		AutoMount:    false,
	}

	err := CreateGlusterVolume(req)
	if err != nil {
		t.Fatalf("CreateGlusterVolume failed: %v", err)
	}

	vols, err := GetGlusterVolumes()
	if err != nil {
		t.Fatalf("GetGlusterVolumes failed: %v", err)
	}

	found := false
	for _, v := range vols {
		if v.Name == "test_vol_2" {
			found = true
			if len(v.Bricks) != 2 {
				t.Errorf("expected 2 bricks, got %d", len(v.Bricks))
			}
			break
		}
	}
	if !found {
		t.Errorf("expected test_vol_2 to be in managed volumes")
	}
}
