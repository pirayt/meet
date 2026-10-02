#!/usr/bin/env bash
# Print a Meet docker-compose deployment's config files with secrets masked,
# plus firewall and disk facts needed to plan an upgrade. Read-only.
#
# Usage (on the server):
#   bash inspect-meet-config.sh /path/to/compose/dir > meet-config.txt 2>&1

set -u
DIR="${1:-.}"

section() { printf '\n===== %s =====\n' "$1"; }

# Masks values of secret-looking keys in env, YAML and JSON, every entry of
# LiveKit's `keys:` block, and credentials embedded in URLs.
mask() {
  python3 - "$1" <<'PY'
import re, sys
SECRET = re.compile(r'(pass|secret|token|key|salt|private|credential)', re.I)
in_keys_block = False
block_indent = None  # indent of a secret YAML block scalar being masked
for line in open(sys.argv[1], errors='replace'):
    line = line.rstrip('\n')
    indent = len(line) - len(line.lstrip())
    if block_indent is not None:
        if line.strip() and indent > block_indent:
            print(' ' * indent + '***'); continue
        block_indent = None
    # LiveKit api keys: "keys:" followed by indented "APIxxx: secret" lines
    if re.match(r'^\s*keys:\s*$', line):
        in_keys_block = True
        print(line); continue
    if in_keys_block:
        if re.match(r'^\s+\S+\s*:', line):
            print(re.sub(r'^(\s+)\S+(\s*:).*', r'\1***\2 ***', line)); continue
        in_keys_block = False
    line = re.sub(r'(://[^:/@\s]+:)[^@\s]+@', r'\1***@', line)
    # JSON "secretKey": "value" pairs anywhere on the line
    line = re.sub(r'("([^"]*)"\s*:\s*)"[^"]*"',
                  lambda m: m.group(1) + '"***"' if SECRET.search(m.group(2)) else m.group(0),
                  line)
    m = re.match(r'^(\s*-?\s*"?)([A-Za-z0-9_.\-]+)("?\s*[:=]\s*)(.+)$', line)
    if m and SECRET.search(m.group(2)):
        if m.group(4).strip() in ('|', '>', '|-', '>-'):
            block_indent = indent
        elif not m.group(4).startswith('"***"'):
            line = f'{m.group(1)}{m.group(2)}{m.group(3)}***'
    print(line)
PY
}

show() {
  [ -f "$1" ] || { echo "(no $1)"; return; }
  section "$1"
  mask "$1"
}

cd "$DIR" || exit 1
show docker-compose.yaml
show docker-compose-authelia.yml
show livekit.yaml
show backend-entrypoint.sh
show caddy-multiplex.yaml
show redis.conf
for f in /etc/nginx/sites-enabled/*; do show "$f"; done

section "frontend-overlay"
ls -la frontend-overlay 2>/dev/null

section "LiveKit version"
for c in $(docker ps --format '{{.Names}} {{.Image}}' | awk '/livekit-server/ {print $1}'); do
  docker exec "$c" /livekit-server --version 2>/dev/null \
    || docker logs "$c" 2>&1 | grep -m1 -iE 'starting livekit|version' \
    || echo "$c: unknown"
done

section "Backend version"
docker exec backend python -c "import importlib.metadata as m; print(m.version('meet'))" 2>/dev/null \
  || echo "(could not query)"

section "Firewall"
(ufw status verbose 2>/dev/null || echo "ufw not available")
(nft list ruleset 2>/dev/null | grep -E 'chain input|dport|policy' | head -40) || true
iptables -S INPUT 2>/dev/null | head -30

section "Docker disk usage"
docker system df
