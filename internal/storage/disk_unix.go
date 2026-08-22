//go:build !windows

package storage

import "syscall"

func getDiskSpace(path string) (total uint64, free uint64, err error) {
	var stat syscall.Statfs_t
	if err := syscall.Statfs(path, &stat); err != nil {
		return 0, 0, err
	}
	total = stat.Blocks * uint64(stat.Bsize)
	free = stat.Bavail * uint64(stat.Bsize)
	return total, free, nil
}

// GetDiskSpace returns total and free space in bytes for the specified path.
func GetDiskSpace(path string) (total uint64, free uint64, err error) {
	return getDiskSpace(path)
}
