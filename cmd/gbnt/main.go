package main

import (
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
	cli.Version = version
	web.Version = version
}

func main() {
	cli.Execute()
}
