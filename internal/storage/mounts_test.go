package storage

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/mario-ezquerro/gubernator/internal/db"
)

func TestMountsFstabAppendAndRemove(t *testing.T) {
	tempFstab := filepath.Join(t.TempDir(), "fstab")
	_ = os.WriteFile(tempFstab, []byte("# Static Host fstab\n/dev/sda1 / ext4 defaults 0 1\n"), 0644)
	t.Setenv("GBNT_FSTAB_PATH", tempFstab)

	mount := db.StorageMount{
		ID:         "mnt-test-1",
		Name:       "nfs-test",
		Device:     "192.168.1.100:/export/data",
		MountPoint: "/var/contenedores",
		FSType:     "nfs",
		Options:    "rw,hard,intr,_netdev",
		Dump:       0,
		Pass:       0,
	}

	err := appendFstabEntry(mount)
	if err != nil {
		t.Fatalf("appendFstabEntry failed: %v", err)
	}

	raw, err := GetRawFstab()
	if err != nil {
		t.Fatalf("GetRawFstab failed: %v", err)
	}

	if !strings.Contains(raw, "192.168.1.100:/export/data") {
		t.Errorf("fstab does not contain mount line: %s", raw)
	}
	if !strings.Contains(raw, "# BEGIN GBNT MOUNT mnt-test-1") {
		t.Errorf("fstab does not contain begin tag: %s", raw)
	}

	// Remove entry
	err = removeFstabEntry("mnt-test-1")
	if err != nil {
		t.Fatalf("removeFstabEntry failed: %v", err)
	}

	rawAfter, _ := GetRawFstab()
	if strings.Contains(rawAfter, "mnt-test-1") {
		t.Errorf("fstab still contains removed entry: %s", rawAfter)
	}
}
