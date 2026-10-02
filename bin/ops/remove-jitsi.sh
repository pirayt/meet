#!/usr/bin/env bash
# Remove a leftover host-level Jitsi Meet install (jitsi-meet, jicofo,
# jitsi-videobridge, prosody) without touching the dockerised Meet stack.
#
# Safe by construction: prints an inventory, refuses to run if Caddy still
# routes to Jitsi ports or Prosody serves foreign domains, backs up configs
# to /root, and asks for confirmation before changing anything.
#
# Usage (as root):  bash remove-jitsi.sh /path/to/meet/compose/dir

set -uo pipefail
MEET_DIR="${1:?usage: $0 /path/to/meet/compose/dir}"
BACKUP="/root/jitsi-backup-$(date +%Y%m%d-%H%M%S).tar.gz"

section() { printf '\n===== %s =====\n' "$1"; }
die() { echo "ABORT: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root"
[ -d "$MEET_DIR" ] || die "no such dir: $MEET_DIR"

# --- Inventory -------------------------------------------------------------
section "Jitsi / Prosody packages"
PKGS=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' 2>/dev/null \
  | awk '$1 ~ /^([ir]i|rc)/ {print $2}' \
  | grep -E '^(jitsi-|jicofo|jigasi|jibri|prosody|lua-prosody)' || true)
echo "${PKGS:-(none)}"

section "Services"
systemctl list-units --all --no-legend 2>/dev/null \
  | grep -E 'jitsi|jicofo|jvb|videobridge|prosody|nginx' || echo "(none)"

section "Prosody virtual hosts"
VHOSTS=$(grep -hoE '^\s*VirtualHost\s+"[^"]+"' /etc/prosody/prosody.cfg.lua \
  /etc/prosody/conf.d/*.cfg.lua 2>/dev/null | sed -E 's/.*"(.+)"/\1/' | sort -u)
echo "${VHOSTS:-(none)}"

section "Host nginx"
NGINX_ACTIVE=$(systemctl is-active nginx 2>/dev/null || true)
echo "nginx service: ${NGINX_ACTIVE:-not installed}"
ls /etc/nginx/sites-enabled /etc/nginx/conf.d /etc/nginx/modules-enabled 2>/dev/null

section "Let's Encrypt certificates (certbot)"
ls /etc/letsencrypt/live 2>/dev/null || echo "(none)"

# --- Guards ----------------------------------------------------------------
section "Safety checks"
for f in "$MEET_DIR"/caddy-multiplex.json "$MEET_DIR"/caddy.yaml; do
  [ -f "$f" ] || continue
  if grep -qE 'localhost:(5280|5281|9090|8888)|jitsi|prosody' "$f"; then
    die "$f still routes to Jitsi/Prosody ports"
  fi
done
echo "Caddy: no routes to Jitsi ports"

# Every Prosody vhost must be a Jitsi one (the meeting domain or a subdomain
# of it); anything else means Prosody serves something we must not delete.
JITSI_DOMAIN=$(ls /etc/jitsi/meet/*-config.js 2>/dev/null | head -1 | xargs -r basename | sed 's/-config\.js$//')
echo "Jitsi domain: ${JITSI_DOMAIN:-unknown}"
[ -n "$VHOSTS" ] && [ -z "$JITSI_DOMAIN" ] && die "Prosody has hosts but the Jitsi domain is unknown"
for vh in $VHOSTS; do
  case "$vh" in
    localhost|"$JITSI_DOMAIN"|*."$JITSI_DOMAIN") ;;
    *) die "Prosody serves a non-Jitsi host: $vh" ;;
  esac
done
echo "Prosody: only Jitsi hosts"

NGINX_OTHER=$(ls /etc/nginx/sites-enabled 2>/dev/null | grep -vE "^(default|${JITSI_DOMAIN:-__none__}\.conf)$" || true)
[ -n "$NGINX_OTHER" ] && echo "nginx has other sites, nginx itself will be kept: $NGINX_OTHER"

echo
read -r -p "Remove everything listed above (except dockerised Meet)? Type 'yes': " answer
[ "$answer" = "yes" ] || die "cancelled"

# --- Backup ----------------------------------------------------------------
section "Backup -> $BACKUP"
tar czf "$BACKUP" --ignore-failed-read \
  /etc/jitsi /etc/prosody /etc/nginx /var/lib/prosody 2>/dev/null
ls -lh "$BACKUP"

# --- Removal ---------------------------------------------------------------
section "Stopping services"
for s in jitsi-videobridge2 jicofo jigasi prosody; do
  systemctl disable --now "$s" 2>/dev/null && echo "stopped $s"
done

section "Purging packages"
if [ -n "$PKGS" ]; then
  # shellcheck disable=SC2086
  DEBIAN_FRONTEND=noninteractive apt-get purge -y $PKGS
fi
DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y

section "Removing leftovers"
rm -rf /etc/jitsi /usr/share/jitsi-meet /usr/share/jicofo \
  /usr/share/jitsi-videobridge /var/log/jitsi \
  /etc/prosody /var/lib/prosody /var/log/prosody
[ -n "$JITSI_DOMAIN" ] && rm -f \
  "/etc/nginx/sites-enabled/$JITSI_DOMAIN.conf" \
  "/etc/nginx/sites-available/$JITSI_DOMAIN.conf"
rm -f /etc/nginx/modules-enabled/*jitsi* /etc/nginx/modules-available/*jitsi*
for f in /etc/apt/sources.list.d/*; do
  grep -qiE 'jitsi|prosody' "$f" 2>/dev/null && rm -v "$f"
done
rm -fv /usr/share/keyrings/*jitsi* /usr/share/keyrings/*prosody* \
  /etc/apt/keyrings/*jitsi* /etc/apt/keyrings/*prosody* 2>/dev/null
for u in jvb jicofo jigasi prosody; do
  id "$u" >/dev/null 2>&1 && userdel "$u" && echo "deleted user $u"
done
getent group jitsi >/dev/null && groupdel jitsi && echo "deleted group jitsi"

# Host nginx only served Jitsi: if it is stopped and has no other sites,
# remove it too. A running nginx is kept and just reloaded.
if [ -z "$NGINX_OTHER" ] && [ "$NGINX_ACTIVE" != "active" ] && dpkg -s nginx >/dev/null 2>&1; then
  systemctl disable --now nginx 2>/dev/null
  DEBIAN_FRONTEND=noninteractive apt-get purge -y 'nginx*' && \
    DEBIAN_FRONTEND=noninteractive apt-get autoremove --purge -y
  rm -rf /etc/nginx /var/log/nginx
  echo "host nginx removed"
elif [ "$NGINX_ACTIVE" = "active" ]; then
  nginx -t && systemctl reload nginx
fi

if [ -n "$JITSI_DOMAIN" ] && [ -d "/etc/letsencrypt/live/$JITSI_DOMAIN" ] && command -v certbot >/dev/null; then
  certbot delete --non-interactive --cert-name "$JITSI_DOMAIN" && echo "removed Jitsi's certbot certificate (Caddy has its own)"
fi

apt-get update -qq 2>&1 | tail -2

# --- Verify ----------------------------------------------------------------
section "Verify"
echo "Listening on former Jitsi ports (expect nothing):"
ss -tulpn 2>/dev/null | grep -E ':(5222|5269|5280|5281|9090|8888|10000)\b' || echo "  none"
echo "Meet containers:"
docker ps --format '  {{.Names}}: {{.Status}}' | grep -E 'annakisoonit|backend|authelia' || true
[ -n "$JITSI_DOMAIN" ] && echo "HTTPS check: $(curl -s -o /dev/null -w '%{http_code}' "https://$JITSI_DOMAIN/")"
grep -n "${JITSI_DOMAIN:-__none__}" /etc/hosts && echo "(/etc/hosts entry above was added by Jitsi; harmless, remove by hand if you like)"
echo
echo "Done. Config backup: $BACKUP"
