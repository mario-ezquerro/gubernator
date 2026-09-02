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

var version = "v2.59.15"

func init() {
	for _, p := range []string{"VERSION", "/data/VERSION", "/app/VERSION", "../VERSION"} {
		if data, err := os.ReadFile(p); err == nil {
			v := strings.TrimSpace(string(data))
			if v != "" && strings.HasPrefix(v, "v") {
				version = v
				break
			}
		}
	}
	cli.Version = version
	web.Version = version
}

func main() {
	cli.Execute()
}
