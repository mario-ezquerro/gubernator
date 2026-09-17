package main

import (
	"fmt"
	"os"

	"github.com/mario-ezquerro/gubernator/internal/coredns"
)

func main() {
	if err := coredns.EnsureRunning(); err != nil {
		_, _ = fmt.Fprintf(os.Stderr, "error: failed to start CoreDNS: %v\n", err)
		os.Exit(1)
	}
}
