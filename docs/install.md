# Install Gubernator (gbnt)

You must install the Gubernator CLI (`gbnt`) on your machine to manage clusters, interact with the API, or run the Manager daemon itself.

Choose your operating system below to download and install the pre-compiled binary.

---

## Linux

1. Download the latest release:
```bash
curl -LO "https://github.com/mario-ezquerro/gubernator/releases/latest/download/gbnt-linux-amd64"
```

2. Make the `gbnt` binary executable:
```bash
chmod +x gbnt-linux-amd64
```

3. Move the binary to a file location on your system `PATH`:
```bash
sudo mv gbnt-linux-amd64 /usr/local/bin/gbnt
```

4. Verify the installation:
```bash
gbnt --help
```

---

## macOS

You can download the binary depending on your Mac's processor architecture (Intel or Apple Silicon).

### Apple Silicon (M1/M2/M3)

1. Download the binary:
```bash
curl -LO "https://github.com/mario-ezquerro/gubernator/releases/latest/download/gbnt-darwin-arm64"
```

2. Make it executable and move it to your PATH:
```bash
chmod +x gbnt-darwin-arm64
sudo mv gbnt-darwin-arm64 /usr/local/bin/gbnt
```

### Intel (x86_64)

1. Download the binary:
```bash
curl -LO "https://github.com/mario-ezquerro/gubernator/releases/latest/download/gbnt-darwin-amd64"
```

2. Make it executable and move it to your PATH:
```bash
chmod +x gbnt-darwin-amd64
sudo mv gbnt-darwin-amd64 /usr/local/bin/gbnt
```

---

## Windows

1. Download the latest `.exe` release using PowerShell:
```powershell
Invoke-WebRequest -Uri "https://github.com/mario-ezquerro/gubernator/releases/latest/download/gbnt-windows-amd64.exe" -OutFile "gbnt.exe"
```

2. Move the `gbnt.exe` file to a folder of your choice (for example, `C:\Program Files\Gubernator`).

3. Add the folder to your Environment Variables `PATH` so you can use `gbnt` from any terminal:
   - Search for **"Environment Variables"** in the Windows Start menu.
   - Click **"Edit the system environment variables"**.
   - Under the "Advanced" tab, click **"Environment Variables..."**.
   - Find the `Path` variable under "System variables", select it, and click **Edit**.
   - Click **New** and add the path to the folder containing `gbnt.exe`.
   - Click **OK** to save.

4. Open a new PowerShell or Command Prompt window and verify the installation:
```powershell
gbnt --help
```

---

## Running via Docker

You can run Gubernator inside Docker using the multi-stage `Dockerfile`. 

### Build the Image

* **For the local architecture:**
  ```bash
  docker build -t gbnt:latest .
  ```

* **For multiple architectures (Intel, macOS, Raspberry Pi) using buildx:**
  ```bash
  docker buildx build --platform linux/amd64,linux/arm64,linux/arm/v7 -t marioezquerro/gubernator:latest .
  ```

### Run the Container
```bash
docker run -d \
  --name gbnt-manager \
  -p 4000:4000 \
  -p 4001:4001 \
  -p 4002:4002 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  marioezquerro/gubernator:latest serve
```

---


## Compiling from Source

If you prefer to compile Gubernator yourself, ensure you have **Go 1.24+** installed. Note that `CGO_ENABLED=1` is required due to the SQLite dependency.

```bash
git clone https://github.com/mario-ezquerro/gubernator.git
cd gubernator
go build -o gbnt ./cmd/gbnt
sudo mv gbnt /usr/local/bin/gbnt
```

> **Note**: The Flutter Web Dashboard is pre-compiled and embedded in the `internal/web/flutter/` directory. If you need to modify the dashboard UI, install [Flutter SDK](https://flutter.dev) and run `cd web-ui && flutter build web --release --base-href "/"`, then copy the output to `internal/web/flutter/`.

---

## Post-Installation: SRE Monitoring

After installing `gbnt`, you can optionally deploy a full SRE observability stack with a single command:

```bash
gbnt monitor init
```

This deploys cAdvisor, Prometheus, Grafana, Loki, and Promtail on a dedicated Docker network. See the [CLI Reference](cli.md) for details.
