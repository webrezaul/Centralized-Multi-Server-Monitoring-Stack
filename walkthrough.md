# Stack Configuration & Troubleshooting Walkthrough

This walkthrough details the setup of the Let's Encrypt SSL script on the Mother Server and the troubleshooting steps taken to successfully start and verify the agents on the Child Server.

---

## 🔒 1. SSL Installation Script (Mother Server)

We created a dedicated bash script to automate SSL setup on the central hub:
* **Script Location:** [scripts/setup-ssl.sh](scripts/setup-ssl.sh)
* **Actions:** Installs Certbot, pauses Nginx to free port 80, requests Let's Encrypt certs, copies keys, and restarts Nginx.
* **Usage:**
  ```bash
  sudo ./scripts/setup-ssl.sh
  ```

---

## 🛠️ 2. Agent Troubleshooting & Resolutions (Child Server)

During deployment on **Child Server 1 (skylearn360)**, we resolved two critical issues:

### Issue A: Port 8080 Conflict (cAdvisor)
* **Problem:** cAdvisor failed to bind to host port `8080` because it was already allocated to a WordPress container.
* **Resolution:** Changed the cAdvisor host port mapping from `"127.0.0.1:8080:8080"` to `"127.0.0.1:8082:8080"` in both child docker-compose files.

### Issue B: Prometheus Agent Config & Startup Failures
1. **Feature Flag Mismatch:** Modern Prometheus versions use `--agent` instead of the deprecated `--enable-feature=agent` flag. We updated the container command.
2. **Deprecated Parameter:** The `max_retries` option under `queue_config` was deprecated/removed. We removed the line from the YAML configurations.
3. **Environment Expansion:** Prometheus lacks native environment expansion for YAML files. We reverted the `--config.expand-env` flag and ran the interactive `./scripts/setup-agent.sh` to correctly substitute variable placeholders statically.

---

## 📝 3. Troubleshooting Command Reference

Here are the commands used to diagnose and resolve the agent issues:

```bash
# Check container status
docker compose ps

# View real-time logs for Prometheus Agent
docker compose logs prometheus-agent

# Pull latest configurations from GitHub
git pull

# Force discard local modifications and align with GitHub
git fetch --all
git reset --hard origin/main

# Stop and clean up orphaned/created containers
docker compose down

# Run the interactive agent setup configuration wizard
./scripts/setup-agent.sh

# Recreate and start the stack cleanly
docker compose up -d
```

---

## 📊 4. Ingestion & Dashboard Verification

### Prometheus Agent Success Logs
The agent successfully replayed the WAL and is sending metrics to Nginx:

![Prometheus Agent Connection Logs](images/prometheus_agent_logs.png)

### Grafana Multi-Server Overview
The central Grafana dashboard confirms that both `mother-server` and `skylearn360` are reporting online with active CPU comparison metrics:

![Grafana Multi-Server Overview](images/grafana_multi_server_overview.png)

### Docker Container Overview
Resource usage metrics (such as Memory and CPU %) from individual containers on `skylearn360` are being scraped and visualized correctly:

![Grafana Docker Overview](images/grafana_docker_overview.png)
