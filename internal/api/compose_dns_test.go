package api

import (
	"testing"

	"gopkg.in/yaml.v3"
)

func TestComposeDNSUnmarshaling(t *testing.T) {
	yamlWithList := `
services:
  web:
    image: nginx:alpine
    dns:
      - 192.168.252.39
      - 8.8.8.8
    dns_search:
      - gbnt.local
      - gbnt
`
	var fileList ComposeFile
	if err := yaml.Unmarshal([]byte(yamlWithList), &fileList); err != nil {
		t.Fatalf("failed to unmarshal yaml with list dns: %v", err)
	}

	webList, ok := fileList.Services["web"]
	if !ok {
		t.Fatalf("service web not found")
	}
	if len(webList.DNS) != 2 || webList.DNS[0] != "192.168.252.39" || webList.DNS[1] != "8.8.8.8" {
		t.Errorf("unexpected DNS slice: %+v", webList.DNS)
	}
	if len(webList.DnsSearch) != 2 || webList.DnsSearch[0] != "gbnt.local" || webList.DnsSearch[1] != "gbnt" {
		t.Errorf("unexpected DnsSearch slice: %+v", webList.DnsSearch)
	}

	yamlWithScalar := `
services:
  api:
    image: my-api:latest
    dns: 192.168.252.39
    dns_search: gbnt.local
`
	var fileScalar ComposeFile
	if err := yaml.Unmarshal([]byte(yamlWithScalar), &fileScalar); err != nil {
		t.Fatalf("failed to unmarshal yaml with scalar dns: %v", err)
	}

	apiSvc, ok := fileScalar.Services["api"]
	if !ok {
		t.Fatalf("service api not found")
	}
	if len(apiSvc.DNS) != 1 || apiSvc.DNS[0] != "192.168.252.39" {
		t.Errorf("unexpected DNS scalar unmarshal: %+v", apiSvc.DNS)
	}
	if len(apiSvc.DnsSearch) != 1 || apiSvc.DnsSearch[0] != "gbnt.local" {
		t.Errorf("unexpected DnsSearch scalar unmarshal: %+v", apiSvc.DnsSearch)
	}
}
