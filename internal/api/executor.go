package api

import (
	"bytes"
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/mario-ezquerro/gubernator/internal/aqueducts"
	"github.com/mario-ezquerro/gubernator/internal/db"
	"github.com/mario-ezquerro/gubernator/internal/docker"
)

const localManagerNodeID = "node-local-manager"

// startLocalExecutor polls for pending tasks on the local node and remote workers, executing them reliably.
// Exits cleanly when ctx is cancelled.
func startLocalExecutor(ctx context.Context) {
	fmt.Println("[Executor] Cluster task executor started. Watching for pending tasks across nodes...")

	for {
		select {
		case <-ctx.Done():
			fmt.Println("[Executor] Shutting down.")
			return
		case <-time.After(3 * time.Second):
		}

		var pendingTasks []db.Task
		if err := db.DB.Where("status = ?", "pending").Find(&pendingTasks).Error; err != nil {
			continue
		}

		for _, task := range pendingTasks {
			if task.NodeID == "none" || task.NodeID == "" {
				continue
			}

			var svc db.Service
			if err := db.DB.First(&svc, "id = ?", task.ServiceID).Error; err != nil {
				fmt.Printf("[Executor] Task %s: service not found, skipping.\n", task.ID[:8])
				db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{"status": "dead", "error": "service not found"})
				continue
			}

			if task.NodeID == localManagerNodeID {
				// Local Manager Execution
				db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
					"status": "pulling",
					"error":  fmt.Sprintf("Downloading image %s...", svc.Image),
				})
				go executeTask(task, svc)
			} else {
				// Remote Worker Node Execution
				var targetNode db.Node
				if err := db.DB.Where("id = ? OR ip = ?", task.NodeID, task.NodeID).First(&targetNode).Error; err == nil && targetNode.IP != "" && targetNode.IP != "127.0.0.1" {
					db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
						"status": "pulling",
						"error":  fmt.Sprintf("Worker node %s (%s): pulling image %s...", targetNode.ID, targetNode.IP, svc.Image),
					})
					go executeRemoteWorkerTask(task, svc, targetNode)
				}
			}
		}
	}
}

// executeRemoteWorkerTask connects via SSH to the Centurion worker and starts the container.
func executeRemoteWorkerTask(task db.Task, svc db.Service, node db.Node) {
	containerName := "gbnt-" + task.ID
	slog.Info("proactively dispatching container to worker via SSH", "task_id", task.ID[:8], "node", node.ID, "ip", node.IP, "image", svc.Image)

	sshArgs := []string{"-o", "UserKnownHostsFile=/dev/null", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=10"}
	keyCandidates := []string{
		"/root/.ssh/id_ed25519", "/root/.ssh/id_rsa",
		"/data/id_ed25519", "/data/id_rsa",
		"/data/ssh/id_ed25519", "/data/ssh/id_rsa",
	}
	for _, k := range keyCandidates {
		if _, err := os.Stat(k); err == nil {
			sshArgs = append(sshArgs, "-i", k)
			break
		}
	}

	// 1. Pull image on remote worker (with context timeout)
	pullCmd := fmt.Sprintf("sudo docker pull '%s'", strings.ReplaceAll(svc.Image, "'", "'\\''"))
	pullSSHArgs := append(append([]string{}, sshArgs...), fmt.Sprintf("ubuntu@%s", node.IP), pullCmd)
	_ = exec.Command("ssh", pullSSHArgs...).Run()

	db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
		"status": "starting",
		"error":  fmt.Sprintf("Worker node %s: starting container...", node.ID),
	})

	// 2. Build docker run arguments with safe single quoting
	var dockerArgs []string
	dockerArgs = append(dockerArgs, "sudo", "docker", "run", "-d", "--restart", "unless-stopped", "--name", fmt.Sprintf("'%s'", containerName), "-l", fmt.Sprintf("'gbnt.task.id=%s'", task.ID))

	if svc.CpuLimit != "" {
		dockerArgs = append(dockerArgs, "--cpus", fmt.Sprintf("'%s'", svc.CpuLimit))
	}
	if svc.MemoryLimit != "" {
		dockerArgs = append(dockerArgs, "--memory", fmt.Sprintf("'%s'", svc.MemoryLimit))
	}
	if svc.MemoryReservation != "" {
		dockerArgs = append(dockerArgs, "--memory-reservation", fmt.Sprintf("'%s'", svc.MemoryReservation))
	}

	for _, p := range svc.Ports {
		dockerArgs = append(dockerArgs, "-p", fmt.Sprintf("'%s'", strings.ReplaceAll(p, "'", "'\\''")))
	}
	for _, e := range svc.Env {
		dockerArgs = append(dockerArgs, "-e", fmt.Sprintf("'%s'", strings.ReplaceAll(e, "'", "'\\''")))
	}
	for _, v := range svc.Volumes {
		dockerArgs = append(dockerArgs, "-v", fmt.Sprintf("'%s'", strings.ReplaceAll(v, "'", "'\\''")))
	}
	dockerArgs = append(dockerArgs, fmt.Sprintf("'%s'", strings.ReplaceAll(svc.Image, "'", "'\\''")))
	if svc.Command != "" {
		for _, tok := range docker.SplitCommand(svc.Command) {
			dockerArgs = append(dockerArgs, fmt.Sprintf("'%s'", strings.ReplaceAll(tok, "'", "'\\''")))
		}
	}

	runCmd := strings.Join(dockerArgs, " ")
	runSSHArgs := append(append([]string{}, sshArgs...), fmt.Sprintf("ubuntu@%s", node.IP), runCmd)

	var runStdout, runStderr bytes.Buffer
	startCmd := exec.Command("ssh", runSSHArgs...)
	startCmd.Stdout = &runStdout
	startCmd.Stderr = &runStderr
	if err := startCmd.Run(); err != nil {
		errMsg := strings.TrimSpace(runStderr.String())
		if errMsg == "" {
			errMsg = err.Error()
		}
		slog.Error("failed to start container on worker via SSH", "task_id", task.ID[:8], "err", errMsg)
		db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
			"status": "dead",
			"error":  fmt.Sprintf("Worker node %s start failed: %s", node.ID, errMsg),
		})
		return
	}

	// 3. Obtain container IP on remote worker (fallback to node.IP)
	ipCmd := fmt.Sprintf("sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' '%s'", containerName)
	ipSSHArgs := append(append([]string{}, sshArgs...), fmt.Sprintf("ubuntu@%s", node.IP), ipCmd)
	var ipOut bytes.Buffer
	inspectCmd := exec.Command("ssh", ipSSHArgs...)
	inspectCmd.Stdout = &ipOut
	_ = inspectCmd.Run()
	containerIP := strings.TrimSpace(ipOut.String())
	if containerIP == "" {
		containerIP = node.IP
	}

	slog.Info("container successfully started on worker", "task_id", task.ID[:8], "container", containerName, "ip", containerIP)
	db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
		"status":         "running",
		"container_ip":   containerIP,
		"container_name": containerName,
		"cpu_limit":      svc.CpuLimit,
		"memory_limit":   svc.MemoryLimit,
		"error":          "",
	})
}

// executeTask pulls the image and starts the container for a given task+service.
func executeTask(task db.Task, svc db.Service) {
	fmt.Printf("[Executor] Task %s: pulling image %s...\n", task.ID[:8], svc.Image)
	db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
		"status": "pulling",
		"error":  fmt.Sprintf("Downloading image %s...", svc.Image),
	})

	if err := docker.PullImage(svc.Image); err != nil {
		fmt.Printf("[Executor] Task %s: pull failed: %v\n", task.ID[:8], err)
		db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{"status": "dead", "error": fmt.Sprintf("pull failed: %v", err)})
		return
	}

	db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
		"status": "starting",
		"error":  "Starting container...",
	})

	cfg := docker.ContainerConfig{
		TaskID:            task.ID,
		Image:             svc.Image,
		Ports:             svc.Ports,
		Env:               svc.Env,
		Volumes:           svc.Volumes,
		Command:           svc.Command,
		CpuLimit:          svc.CpuLimit,
		MemoryLimit:       svc.MemoryLimit,
		MemoryReservation: svc.MemoryReservation,
	}

	containerName, ip, err := docker.StartContainer(cfg)
	if err != nil {
		fmt.Printf("[Executor] Task %s: start failed: %v\n", task.ID[:8], err)
		db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{"status": "dead", "error": fmt.Sprintf("start failed: %v", err)})
		return
	}

	fmt.Printf("[Executor] Task %s: container %s started (IP: %s)\n", task.ID[:8], containerName, ip)

	db.DB.Model(&db.Task{}).Where("id = ?", task.ID).Updates(map[string]interface{}{
		"status":         "running",
		"container_ip":   ip,
		"container_name": containerName,
		"error":          "",
	})

	// Update DNS and Ingress
	go func() {
		aqueducts.GenerateHostsFile()
		aqueducts.GenerateCaddyfile()
	}()
}

// StopTaskOnNode stops and removes a container on its assigned node (local manager or remote worker via SSH).
func StopTaskOnNode(task db.Task) error {
	containerName := task.ContainerName
	if containerName == "" {
		if len(task.ID) >= 8 {
			containerName = "gbnt-" + task.ID
		} else {
			return nil
		}
	}

	if task.NodeID == localManagerNodeID || task.NodeID == "" || strings.Contains(strings.ToLower(task.NodeID), "manager") {
		_ = docker.StopContainer(containerName)
		_ = exec.Command("docker", "rm", "-f", containerName).Run()
		return nil
	}

	// Remote worker node via SSH
	var targetNode db.Node
	if err := db.DB.First(&targetNode, "id = ? OR ip = ?", task.NodeID, task.NodeID).Error; err == nil && targetNode.IP != "" {
		sshArgs := []string{"-o", "UserKnownHostsFile=/dev/null", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5"}
		keyCandidates := []string{
			"/root/.ssh/id_ed25519", "/root/.ssh/id_rsa",
			"/data/id_ed25519", "/data/id_rsa",
			"/data/ssh/id_ed25519", "/data/ssh/id_rsa",
			"/home/ubuntu/.ssh/id_ed25519", "/home/ubuntu/.ssh/id_rsa",
		}
		for _, k := range keyCandidates {
			if _, err := os.Stat(k); err == nil {
				sshArgs = append(sshArgs, "-i", k)
				break
			}
		}
		stopCmd := fmt.Sprintf("sudo docker rm -f %s 2>/dev/null || true", containerName)
		stopSSHArgs := append(append([]string{}, sshArgs...), fmt.Sprintf("ubuntu@%s", targetNode.IP), stopCmd)
		_ = exec.Command("ssh", stopSSHArgs...).Run()
	} else {
		_ = docker.StopContainer(containerName)
		_ = exec.Command("docker", "rm", "-f", containerName).Run()
	}
	return nil
}

// StopStackContainers stops and removes all containers belonging to a stack's tasks across all nodes.
func StopStackContainers(stackID string) {
	var services []db.Service
	db.DB.Where("stack_id = ?", stackID).Find(&services)

	for _, svc := range services {
		var tasks []db.Task
		db.DB.Where("service_id = ?", svc.ID).Find(&tasks)

		for _, task := range tasks {
			fmt.Printf("[Executor] Stopping container %s on node %s for task %s...\n", task.ContainerName, task.NodeID, task.ID[:8])
			_ = StopTaskOnNode(task)
		}
	}
}
