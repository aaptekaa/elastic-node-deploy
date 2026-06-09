# elk-deploy

One-command Elasticsearch + Kibana installer for Debian-based systems.

Installs and fully configures a production-ready single-node ELK stack with security enabled, TLS, Fleet support, and encryption keys — no manual steps required.

---

## Quick Start

```bash
wget https://github.com/aaptekaa/elastic-node-deploy/blob/main/elk-deploy.sh
bash elk-deploy.sh
```

> Must be run as **root**.

---

## What It Does

The script runs through **7 steps** and handles everything automatically:

| Step | Action |
|------|--------|
| 1 | Checks system requirements (RAM, disk, OS) |
| 2 | Installs prerequisites: `curl`, `gnupg`, `python3`, etc. |
| 3 | Adds the official Elastic APT repository |
| 4 | Installs **Elasticsearch 9.4.2** |
| 5 | Installs **Kibana 9.4.2** |
| 6 | Asks for network config (bind address, cluster name, password) |
| 7 | Configures both services, sets passwords, generates encryption keys, starts everything |

At the end it prints the Kibana URL, Elasticsearch URL, username, and password.

---

## Requirements

| Requirement | Details |
|-------------|---------|
| OS | Debian 10 / 11 / 12 or Ubuntu 20.04+ |
| RAM | 4 GB minimum (16 GB recommended) |
| Disk | 10 GB free minimum |
| Internet | Required to download packages (~1.3 GB) |
| User | root |

---

## Interactive Configuration

After packages are downloaded, the script asks 5 questions:

```
Elasticsearch bind address  [0.0.0.0]:    ← press Enter for default
Kibana bind address         [0.0.0.0]:    ← press Enter for default
Cluster name                [elasticsearch]:
Node name                   [hostname]:
Password (min 8 chars):
```

Press **Enter** to accept the default. Only the password is required.

---

## What Gets Configured

**Elasticsearch (`/etc/elasticsearch/elasticsearch.yml`):**
- `discovery.type: single-node`
- `network.host` — your chosen bind address
- Security enabled with HTTPS and auto-generated TLS certificates
- Snapshot repository path at `/var/backups/elasticsearch`

**Kibana (`/etc/kibana/kibana.yml`):**
- Connected to Elasticsearch via service account token
- Encryption keys for Fleet, Alerting, and Reporting
- `server.publicBaseUrl` set to the detected server IP

---

## After Installation

```bash
# Check services
systemctl status elasticsearch kibana

# View logs
journalctl -u elasticsearch -f
journalctl -u kibana -f

# Restart
systemctl restart elasticsearch kibana
```

**Kibana UI:** `http://YOUR_IP:5601`  
**Elasticsearch API:** `https://YOUR_IP:9200`  
**Login:** `elastic` / your chosen password

---

## Install Log

Full installation log is saved to:
```
/var/log/elk-install.log
```
<img width="450" height="444" alt="image" src="https://github.com/user-attachments/assets/50177de6-5ac3-4318-b26b-e53e4a7a1508" />

---

## Notes

- Safe to re-run on the same server — existing config is backed up to `.bak` before changes
- Encryption keys are regenerated on each run (`--force`) — existing sessions will be invalidated
- The script removes conflicting `cluster.initial_master_nodes` that Debian/Ubuntu packages add by default
