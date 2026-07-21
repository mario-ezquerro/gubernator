package main

import (
	"os"
	"strings"

	"github.com/mario-ezquerro/gubernator/internal/cli"
	"github.com/mario-ezquerro/gubernator/internal/web"
)

// @title           Gubernator API
// @version         1.0
// @description     This is the API Server for Gubernator orchestration.
// @host            localhost:4002
// @BasePath        /

var version = "dev"

func init() {
	if version == "dev" {
		for _, path := range []string{"VERSION", "/app/VERSION", "../VERSION"} {
			if data, err := os.ReadFile(path); err == nil {
				v := strings.TrimSpace(string(data))
				if v != "" {
					version = v
					break
				}
			}
		}
	}
	cli.Version = version
	web.Version = version
}

func main() {
	cli.Execute()
}
