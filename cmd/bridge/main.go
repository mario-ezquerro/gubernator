package main

import (
	"fmt"
	"io"
	"log"
	"net"
	"sync"
)

func forward(localPort int, remoteTarget string) {
	listener, err := net.Listen("tcp", fmt.Sprintf("0.0.0.0:%d", localPort))
	if err != nil {
		log.Printf("Failed to listen on 0.0.0.0:%d: %v", localPort, err)
		return
	}
	defer listener.Close()
	log.Printf("🚀 Forwarding localhost:%d -> %s", localPort, remoteTarget)

	for {
		clientConn, err := listener.Accept()
		if err != nil {
			log.Printf("Accept error on :%d: %v", localPort, err)
			continue
		}

		go func(c net.Conn) {
			defer c.Close()
			remoteConn, err := net.Dial("tcp", remoteTarget)
			if err != nil {
				log.Printf("Failed to connect to %s: %v", remoteTarget, err)
				return
			}
			defer remoteConn.Close()

			var wg sync.WaitGroup
			wg.Add(2)

			go func() {
				defer wg.Done()
				_, _ = io.Copy(remoteConn, c)
			}()

			go func() {
				defer wg.Done()
				_, _ = io.Copy(c, remoteConn)
			}()

			wg.Wait()
		}(clientConn)
	}
}

func main() {
	managerIP := "192.168.252.31"
	log.Println("Starting Gubernator Host Port Bridge for macOS...")

	go forward(4001, fmt.Sprintf("%s:4001", managerIP))
	go forward(4000, fmt.Sprintf("%s:4000", managerIP))
	go forward(3000, fmt.Sprintf("%s:3000", managerIP))
	go forward(16686, fmt.Sprintf("%s:16686", managerIP))
	go forward(8080, fmt.Sprintf("%s:80", managerIP))

	select {}
}
