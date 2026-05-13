package main

import (
	"github.com/mario-ezquerro/gubernator/internal/cli"
)

// @title           Gubernator API
// @version         1.0
// @description     This is the API Server for Gubernator orchestration.
// @host            localhost:4000
// @BasePath        /
func main() {
	cli.Execute()
}
