#!/bin/bash
# =============================================================================
#  elk-deploy.sh  —  Elasticsearch + Kibana 9.4.2
#  Single-Node Installer for Debian 10 / 11 / 12
#  Usage: bash elk-deploy.sh   (run as root)
# =============================================================================
set -euo pipefail

ELK_VERSION="9.4.2"
LOG_FILE="/var/log/elk-install.log"

# Colors
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'; B='\033[1m'; N='\033[0m'
_S=0; _T=7

mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1

step()  { _S=$((_S+1)); echo -e "\n${B}${C}[ STEP ${_S}/${_T} ]  $*${N}"; }
log()   { echo -e "     --> $*"; }
ok()    { echo -e "     ${G}[OK]${N}  $*"; }
warn()  { echo -e "     ${Y}[!!]${N}  $*"; }
fail()  { echo -e "\n     ${R}[FAIL]${N}  $*\n     Log: ${LOG_FILE}\n"; exit 1; }
hr()    { echo -e "${C}  ─────────────────────────────────────────────────────${N}"; }

# ── Banner ────────────────────────────────────────────────────────────────────
clear
echo ""
hr
echo -e "\n  ${B}  Elasticsearch + Kibana ${ELK_VERSION}${N}"
echo -e   "  ${C}  Single-Node Installer for Debian${N}"
echo -e   "  ${C}  Log: ${LOG_FILE}${N}\n"
hr
echo ""

# ── Pre-flight ────────────────────────────────────────────────────────────────
[[ "$EUID" -ne 0 ]] && fail "Run as root: sudo bash elk-deploy.sh"
ok "Running as root"

if ! grep -qi "debian\|ubuntu" /etc/os-release 2>/dev/null; then
  warn "OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo unknown)"
  read -rp "     Continue anyway? [y/N]: " _C
  [[ "${_C,,}" != "y" ]] && exit 0
fi
ok "OS: $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"

RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
[[ $RAM_MB -lt 3800 ]] \
  && warn "RAM: ${RAM_MB}MB — Elasticsearch recommends 4GB+" \
  || ok "RAM: ${RAM_MB}MB"

DISK_MB=$(df / --output=avail -BM 2>/dev/null | tail -1 | tr -d 'M')
[[ ${DISK_MB:-0} -lt 5120 ]] \
  && fail "Disk: ${DISK_MB}MB free on / — need at least 5GB" \
  || ok "Disk: ${DISK_MB}MB free on /"

# ── STEP 1: Prerequisites ─────────────────────────────────────────────────────
step "Prerequisites"

NEEDED=()
for pkg in curl gnupg apt-transport-https ca-certificates lsb-release python3; do
  if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
    ok "$pkg"
  else
    log "Will install: $pkg"
    NEEDED+=("$pkg")
  fi
done

if [[ ${#NEEDED[@]} -gt 0 ]]; then
  log "Updating package lists..."
  apt-get update -qq
  log "Installing: ${NEEDED[*]}"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${NEEDED[@]}"
  ok "Packages installed"
fi

# ── STEP 2: Elastic APT repository ───────────────────────────────────────────
step "Elastic APT repository"

if [[ ! -f /usr/share/keyrings/elasticsearch-keyring.gpg ]]; then
  log "Importing Elastic GPG key..."
  curl -fsSL https://artifacts.elastic.co/GPG-KEY-elasticsearch \
    | gpg --dearmor -o /usr/share/keyrings/elasticsearch-keyring.gpg 2>/dev/null
  ok "GPG key imported"
else
  ok "GPG key — already present"
fi

if [[ ! -f /etc/apt/sources.list.d/elastic-9.x.list ]]; then
  log "Adding Elastic 9.x repository..."
  echo "deb [signed-by=/usr/share/keyrings/elasticsearch-keyring.gpg] https://artifacts.elastic.co/packages/9.x/apt stable main" \
    > /etc/apt/sources.list.d/elastic-9.x.list
  ok "Repository added: elastic-9.x"
else
  ok "Repository — already configured"
fi

log "Updating package lists..."
apt-get update -qq

AVAILABLE=$(apt-cache policy elasticsearch 2>/dev/null | grep "${ELK_VERSION}" | head -1 | xargs 2>/dev/null || true)
[[ -z "$AVAILABLE" ]] && fail "Version ${ELK_VERSION} not found in repository. Check internet access."
ok "elasticsearch=${ELK_VERSION} found in repository"

# ── STEP 3: Install Elasticsearch ────────────────────────────────────────────
step "Installing Elasticsearch ${ELK_VERSION}"

ES_CURRENT=$(dpkg -l elasticsearch 2>/dev/null | grep "^ii" | awk '{print $3}' || true)
if [[ "$ES_CURRENT" == "$ELK_VERSION" ]]; then
  ok "Elasticsearch ${ELK_VERSION} — already installed"
else
  log "Downloading Elasticsearch (~800 MB)..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    -o Dpkg::Options::="--force-confold" \
    elasticsearch="${ELK_VERSION}"
  ok "Elasticsearch ${ELK_VERSION} installed"
fi

# ── STEP 4: Install Kibana ────────────────────────────────────────────────────
step "Installing Kibana ${ELK_VERSION}"

KB_CURRENT=$(dpkg -l kibana 2>/dev/null | grep "^ii" | awk '{print $3}' || true)
if [[ "$KB_CURRENT" == "$ELK_VERSION" ]]; then
  ok "Kibana ${ELK_VERSION} — already installed"
else
  log "Downloading Kibana (~450 MB)..."
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    -o Dpkg::Options::="--force-confold" \
    kibana="${ELK_VERSION}"
  ok "Kibana ${ELK_VERSION} installed"
fi

# ── STEP 5: Network configuration ────────────────────────────────────────────
step "Network configuration"

hr
echo ""
echo -e "  ${B}Packages installed. Configure the stack below.${N}"
echo -e "  Press ENTER to keep the default value shown in brackets."
echo ""

AUTO_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/{print $7}' | head -1 \
  || hostname -I 2>/dev/null | awk '{print $1}')
AUTO_HOST=$(hostname -s 2>/dev/null || echo "elk-node")

echo -e "  Detected server IP : ${B}${AUTO_IP}${N}   Hostname: ${B}${AUTO_HOST}${N}"
echo ""

read -rp "  Elasticsearch bind address  [0.0.0.0]: "        ES_BIND;    ES_BIND=${ES_BIND:-0.0.0.0}
read -rp "  Kibana bind address         [0.0.0.0]: "        KB_BIND;    KB_BIND=${KB_BIND:-0.0.0.0}
read -rp "  Cluster name                [elasticsearch]: "  CLUSTER;    CLUSTER=${CLUSTER:-elasticsearch}
read -rp "  Node name                   [${AUTO_HOST}]: "   NODE_NAME;  NODE_NAME=${NODE_NAME:-${AUTO_HOST}}

echo ""
echo -e "  ${B}Elastic superuser password${N}"
ELASTIC_PASS=""
while true; do
  read -rsp "  Password (min 8 chars): " ELASTIC_PASS; echo ""
  if [[ ${#ELASTIC_PASS} -lt 8 ]]; then warn "Too short — minimum 8 characters"; continue; fi
  read -rsp "  Confirm password:       " _P2; echo ""
  if [[ "$ELASTIC_PASS" != "$_P2" ]]; then warn "Passwords do not match"; continue; fi
  break
done

if [[ "$ES_BIND" == "0.0.0.0" ]]; then
  ES_CURL="127.0.0.1"
else
  ES_CURL="$ES_BIND"
fi

echo ""
ok "Elasticsearch : ${ES_BIND}:9200  (internal: ${ES_CURL})"
ok "Kibana        : ${KB_BIND}:5601"
ok "Cluster name  : ${CLUSTER}"
ok "Node name     : ${NODE_NAME}"
ok "Password      : configured"

# ── STEP 6: Configure and start Elasticsearch ─────────────────────────────────
step "Configuring and starting Elasticsearch"

cp /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.yml.bak 2>/dev/null || true

export _ES_BIND="$ES_BIND"
export _CLUSTER="$CLUSTER"
export _NODE="$NODE_NAME"

python3 << 'PYEOF'
import re, os

path = '/etc/elasticsearch/elasticsearch.yml'
try:
    with open(path) as f:
        content = f.read()
except FileNotFoundError:
    content = ''

def upsert(text, key, value):
    pat = r'^#?\s*' + re.escape(key) + r'\s*:.*$'
    line = f'{key}: {value}'
    return re.sub(pat, line, text, flags=re.MULTILINE) \
           if re.search(pat, text, re.MULTILINE) else text + f'\n{line}\n'

for k, v in {
    'cluster.name':                        os.environ['_CLUSTER'],
    'node.name':                           os.environ['_NODE'],
    'network.host':                        os.environ['_ES_BIND'],
    'http.port':                           '9200',
    'discovery.type':                      'single-node',
    'xpack.security.enrollment.enabled':   'false',
}.items():
    content = upsert(content, k, v)

# Удалить конфликтующие настройки из дефолтного yml Debian/Ubuntu
content = re.sub(r'^cluster\.initial_master_nodes:.*\n?', '', content, flags=re.MULTILINE)
content = re.sub(r'^http\.host:.*\n?', '', content, flags=re.MULTILINE)

if 'path.repo' not in content:
    content += '\npath.repo: ["/var/backups/elasticsearch"]\n'

with open(path, 'w') as f:
    f.write(content)

print('     --> /etc/elasticsearch/elasticsearch.yml updated')
PYEOF

mkdir -p /var/backups/elasticsearch
chown elasticsearch:elasticsearch /var/backups/elasticsearch

systemctl daemon-reload
systemctl enable elasticsearch --quiet
log "Starting Elasticsearch (first start: 3-5 minutes)..."
systemctl restart elasticsearch

log "Waiting for Elasticsearch to respond..."
DEADLINE=$((SECONDS + 360))
while true; do
  CODE=$(curl -sk "https://${ES_CURL}:9200/" -o /dev/null -w '%{http_code}' 2>/dev/null || true)
  if [[ "$CODE" =~ ^(200|401)$ ]]; then
    echo ""
    ok "Elasticsearch responding (HTTP $CODE)"
    sleep 3
    break
  fi
  if [[ $SECONDS -ge $DEADLINE ]]; then
    echo ""
    fail "Elasticsearch did not start in 6 minutes.\nDiagnose: journalctl -u elasticsearch -n 50"
  fi
  printf "\r     . %ds remaining..." $((DEADLINE - SECONDS))
  sleep 10
done

log "Resetting elastic user password..."
RESET_OUT=$(/usr/share/elasticsearch/bin/elasticsearch-reset-password \
  -u elastic -b --url "https://${ES_CURL}:9200" 2>&1 || true)
TEMP_PASS=$(echo "$RESET_OUT" | grep -i "new value" | awk '{print $NF}' | tr -d '[:space:]\r\n')
[[ -z "$TEMP_PASS" ]] && fail "Password reset failed.\nOutput: $RESET_OUT"
ok "Temporary credentials obtained"

log "Setting elastic user password..."
_RESP=$(curl -sk -u "elastic:${TEMP_PASS}" \
  -X POST "https://${ES_CURL}:9200/_security/user/elastic/_password" \
  -H "Content-Type: application/json" \
  -d "{\"password\": \"${ELASTIC_PASS}\"}" \
  -w "\nHTTP:%{http_code}" 2>/dev/null)
echo "$_RESP" | grep -q "HTTP:200" \
  || fail "Failed to set elastic password.\nResponse: $_RESP"
ok "Elastic password set"

_VER=$(curl -sk -u "elastic:${ELASTIC_PASS}" "https://${ES_CURL}:9200/" 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["version"]["number"])' 2>/dev/null || true)
[[ -n "$_VER" ]] \
  && ok "Elasticsearch ${_VER} — authentication OK" \
  || fail "Authentication failed with the new password"

# ── STEP 7: Configure and start Kibana ───────────────────────────────────────
step "Configuring and starting Kibana"

log "Creating Kibana service account token..."
_TR=$(curl -sk -u "elastic:${ELASTIC_PASS}" \
  -X POST "https://${ES_CURL}:9200/_security/service/elastic/kibana/credential/token/kibana_token" \
  -H "Content-Type: application/json" 2>/dev/null)
KB_TOKEN=$(echo "$_TR" | python3 -c \
  'import json,sys; print(json.load(sys.stdin)["token"]["value"])' 2>/dev/null || true)
[[ -z "$KB_TOKEN" ]] && fail "Could not create Kibana token.\nResponse: $_TR"
ok "Kibana service account token created"

log "Copying Elasticsearch CA certificate..."
mkdir -p /etc/kibana/certs
if [[ -f /etc/elasticsearch/certs/http_ca.crt ]]; then
  cp /etc/elasticsearch/certs/http_ca.crt /etc/kibana/certs/es-ca.pem
  chown -R kibana:kibana /etc/kibana/certs
  CA_PRESENT="yes"
  ok "CA certificate copied to /etc/kibana/certs/es-ca.pem"
else
  CA_PRESENT="no"
  warn "CA cert not found — Kibana will skip SSL verification"
fi

cp /etc/kibana/kibana.yml /etc/kibana/kibana.yml.bak 2>/dev/null || true

export _KB_BIND="$KB_BIND"
export _KB_NAME="$CLUSTER"
export _KB_TOKEN="$KB_TOKEN"
export _SERVER_IP="$AUTO_IP"
export _ES_CURL="$ES_CURL"
export _CA_PRESENT="$CA_PRESENT"

python3 << 'PYEOF'
import re, os

path = '/etc/kibana/kibana.yml'
try:
    with open(path) as f:
        content = f.read()
except FileNotFoundError:
    content = ''

def upsert(text, key, value):
    pat = r'^#?\s*' + re.escape(key) + r'\s*:.*$'
    line = f'{key}: {value}'
    return re.sub(pat, line, text, flags=re.MULTILINE) \
           if re.search(pat, text, re.MULTILINE) else text + f'\n{line}\n'

server_ip = os.environ['_SERVER_IP']
es_curl   = os.environ['_ES_CURL']
kb_token  = os.environ['_KB_TOKEN']
ca_ok     = os.environ.get('_CA_PRESENT', 'no') == 'yes'

settings = {
    'server.host':          f'"{os.environ["_KB_BIND"]}"',
    'server.port':          '5601',
    'server.name':          f'"{os.environ["_KB_NAME"]}"',
    'server.publicBaseUrl': f'"http://{server_ip}:5601"',
    'elasticsearch.hosts':  f'["https://{es_curl}:9200"]',
    'elasticsearch.serviceAccountToken': f'"{kb_token}"',
}

if ca_ok:
    settings['elasticsearch.ssl.certificateAuthorities'] = '["/etc/kibana/certs/es-ca.pem"]'
    settings['elasticsearch.ssl.verificationMode']       = '"certificate"'
else:
    settings['elasticsearch.ssl.verificationMode'] = '"none"'

for k, v in settings.items():
    content = upsert(content, k, v)

with open(path, 'w') as f:
    f.write(content)

print('     --> /etc/kibana/kibana.yml updated')
PYEOF

# KEY GEN (need to Fleet, Alerting, Reporting)
log "Generating Kibana encryption keys..."
ENC_KEYS=$(/usr/share/kibana/bin/kibana-encryption-keys generate --force 2>/dev/null \
  | grep "^xpack\." | grep ":" || true)
if [[ -n "$ENC_KEYS" ]]; then
  python3 -c "
import re, sys
path = '/etc/kibana/kibana.yml'
with open(path) as f:
    content = f.read()
content = re.sub(r'^xpack\.[^\n]*\n?', '', content, flags=re.MULTILINE)
content = content.rstrip() + '\n\n' + sys.argv[1] + '\n'
with open(path, 'w') as f:
    f.write(content)
" "$ENC_KEYS"
  ok "Encryption keys generated and added to kibana.yml"
else
  warn "Could not generate encryption keys — Fleet may show warnings"
fi

systemctl daemon-reload
systemctl enable kibana --quiet
log "Starting Kibana (2-3 minutes)..."
systemctl restart kibana

log "Waiting for Kibana to respond..."
DEADLINE=$((SECONDS + 300))
while true; do
  CODE=$(curl -s "http://${ES_CURL}:5601/api/status" -o /dev/null -w '%{http_code}' 2>/dev/null || true)
  if [[ "$CODE" == "200" ]]; then
    echo ""
    ok "Kibana is ready (HTTP $CODE)"
    break
  fi
  if [[ $SECONDS -ge $DEADLINE ]]; then
    echo ""
    warn "Kibana did not respond in 5 minutes — it may still be initializing"
    warn "Check: journalctl -u kibana -n 50"
    break
  fi
  printf "\r     . %ds remaining..." $((DEADLINE - SECONDS))
  sleep 10
done

# ── Final summary ─────────────────────────────────────────────────────────────
echo ""
hr
echo ""
echo -e "  ${B}${G}Installation complete!${N}"
echo ""
echo -e "  ${B}Stack version   :${N}  Elasticsearch + Kibana ${ELK_VERSION}"
echo ""
echo -e "  ${B}Kibana UI       :${N}  http://${AUTO_IP}:5601"
echo -e "  ${B}Elasticsearch   :${N}  https://${AUTO_IP}:9200"
echo ""
echo -e "  ${B}Username        :${N}  elastic"
echo -e "  ${B}Password        :${N}  ${ELASTIC_PASS}"
echo ""
hr
echo -e "  ${B}Service commands:${N}"
echo "     systemctl status elasticsearch kibana"
echo "     systemctl restart elasticsearch kibana"
echo "     journalctl -u elasticsearch -f"
echo "     journalctl -u kibana -f"
echo ""
echo -e "  ${B}Config files    :${N}"
echo "     /etc/elasticsearch/elasticsearch.yml"
echo "     /etc/kibana/kibana.yml"
echo ""
echo -e "  ${B}Backups         :${N}"
echo "     /etc/elasticsearch/elasticsearch.yml.bak"
echo "     /etc/kibana/kibana.yml.bak"
echo ""
echo -e "  ${B}Install log     :${N}  ${LOG_FILE}"
echo ""
hr
echo ""
