#!/usr/bin/env bash
# Read-only snapshot of a Meet deployment, safe to share.
# It changes nothing and never prints secret values: for environment
# variables and env files only the variable NAMES are shown.
#
# Usage (on the server):  bash inspect-deployment.sh > meet-report.txt 2>&1

set -u

section() { printf '\n===== %s =====\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

# Docker CLI may need sudo; use it only if plain docker is denied.
DOCKER="docker"
if have docker && ! docker info >/dev/null 2>&1 && have sudo; then
  DOCKER="sudo docker"
fi

section "Host"
uname -srm
[ -r /etc/os-release ] && . /etc/os-release && echo "OS: ${PRETTY_NAME:-unknown}"
echo "CPU cores: $(nproc 2>/dev/null || echo '?')"
free -h 2>/dev/null | head -2
df -h / 2>/dev/null | tail -1
uptime

section "Tooling"
for t in docker kubectl helm helmfile k3s nginx caddy traefik certbot livekit-server; do
  if have "$t"; then echo "$t: $(command -v "$t")"; fi
done
have docker && $DOCKER version --format 'docker server {{.Server.Version}}' 2>/dev/null
have docker && $DOCKER compose version 2>/dev/null

if have docker; then
  section "Running containers (name | image | status | ports)"
  $DOCKER ps --format '{{.Names}} | {{.Image}} | {{.Status}} | {{.Ports}}'

  section "Stopped containers"
  $DOCKER ps -a --filter status=exited --format '{{.Names}} | {{.Image}} | {{.Status}}'

  section "Image digests and creation dates"
  $DOCKER ps --format '{{.Image}}' | sort -u | while read -r img; do
    $DOCKER image inspect "$img" \
      --format "$img | created {{.Created}} | {{index .RepoDigests 0}}" 2>/dev/null \
      || echo "$img | (inspect failed)"
  done

  section "Compose projects"
  $DOCKER ps --format '{{.Label "com.docker.compose.project"}}|{{.Label "com.docker.compose.project.working_dir"}}|{{.Label "com.docker.compose.project.config_files"}}' \
    | sort -u | grep -v '^||$'

  section "Environment variable NAMES per container (values hidden)"
  for c in $($DOCKER ps --format '{{.Names}}'); do
    echo "--- $c"
    $DOCKER inspect "$c" --format '{{range .Config.Env}}{{println .}}{{end}}' \
      | cut -d= -f1 | grep -vE '^(PATH|HOME|HOSTNAME|LANG|GPG_KEY|PYTHON_.*|NODE_VERSION|YARN_VERSION|NGINX_VERSION|PKG_RELEASE|NJS_.*)$' \
      | sort | tr '\n' ' '
    echo
  done

  section "LiveKit server version"
  for c in $($DOCKER ps --format '{{.Names}} {{.Image}}' | awk '/livekit-server/ {print $1}'); do
    echo "$c: $($DOCKER exec "$c" /livekit-server --version 2>/dev/null || echo '(could not query)')"
  done
fi

if have kubectl; then
  section "Kubernetes workloads"
  kubectl get deploy,statefulset,ingress -A -o wide 2>/dev/null | grep -iE 'meet|livekit|NAME' || echo "(no access or nothing found)"
fi

section "Compose and env files near the project (names of variables only)"
for dir in $($DOCKER ps --format '{{.Label "com.docker.compose.project.working_dir"}}' 2>/dev/null | sort -u); do
  [ -d "$dir" ] || continue
  echo "--- $dir"
  ls -la "$dir"
  find "$dir" -maxdepth 3 \( -name '*.env' -o -name '.env' -o -path '*env.d*' -type f \) 2>/dev/null | while read -r f; do
    echo "  [$f] $(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$f" | cut -d= -f1 | sort | tr '\n' ' ')"
  done
  [ -d "$dir/.git" ] && echo "  git: $(git -C "$dir" log -1 --format='%h %ad %s' --date=short 2>/dev/null) ($(git -C "$dir" remote get-url origin 2>/dev/null))"
done

section "Reverse proxy sites"
ls /etc/nginx/sites-enabled /etc/nginx/conf.d /etc/caddy 2>/dev/null

section "Listening ports"
(ss -tulpn 2>/dev/null || netstat -tulpn 2>/dev/null) | awk 'NR==1 || /LISTEN|udp/' | head -40

echo
echo "Done. Review the report before sharing it."
