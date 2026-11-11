#!/usr/bin/env bash
# Gather Facter facts on Linux by installing a pinned Puppet Core puppet-agent.
# Runs as root inside the platform container.
#
# Env: PUPPET_FORGE_TOKEN (secret), FACTER_VERSION, AGENT_VERSION, AGENT_MAJOR, PLATFORM_ID,
#      OUT_DIR, REPO_ID (apt codename or el-N/fedora-N/amazon-N).
# Exit: 0 and OUT_DIR/result.json for gathered (plus facts.json) or skipped (no Core package);
#       non-zero for bad input (2) or any credential, network, install or version error.
# The token is only read through awk ENVIRON; it is never placed in argv, logged or written to OUT_DIR.
set -euo pipefail

for name in PUPPET_FORGE_TOKEN FACTER_VERSION AGENT_VERSION AGENT_MAJOR PLATFORM_ID OUT_DIR REPO_ID; do
  if [[ -z "${!name:-}" ]]; then
    echo "missing required env var: ${name}" >&2
    exit 2
  fi
done

if [[ ! "${FACTER_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  [[ ! "${AGENT_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  [[ ! "${AGENT_MAJOR}" =~ ^[0-9]+$ ]] ||
  [[ ! "${REPO_ID}" =~ ^[a-z0-9.-]+$ ]] ||
  [[ ! "${PLATFORM_ID}" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "invalid input" >&2
  exit 2
fi

facter_bin=/opt/puppetlabs/bin/facter

write_result() {
  mkdir -p "${OUT_DIR}"
  printf '{"id":"%s","outcome":"%s","reason":"%s"}\n' "${PLATFORM_ID}" "$1" "$2" > "${OUT_DIR}/result.json"
}

skip() {
  write_result skipped "$1"
  echo "skipped: $1"
  exit 0
}

if command -v apt-get > /dev/null 2>&1; then
  pm=apt
elif command -v dnf > /dev/null 2>&1; then
  pm=dnf
elif command -v yum > /dev/null 2>&1; then
  pm=yum
else
  echo "unsupported package manager" >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

if [[ "${pm}" == apt ]]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates gnupg > /dev/null
  pkg_file="${work}/release.deb"
  url="https://apt-puppetcore.puppet.com/public/puppet${AGENT_MAJOR}-release-${REPO_ID}.deb"
else
  "${pm}" install -y -q curl ca-certificates > /dev/null
  pkg_file="${work}/release.rpm"
  url="https://yum-puppetcore.puppet.com/public/puppet${AGENT_MAJOR}-release-${REPO_ID}.noarch.rpm"
fi

status="$(curl -sS -L -o "${pkg_file}" -w '%{http_code}' "${url}")"
if [[ "${status}" == 404 ]]; then
  skip "No puppet${AGENT_MAJOR}-release package for ${REPO_ID}"
elif [[ "${status}" != 200 ]]; then
  echo "release package download failed with HTTP ${status}" >&2
  exit 1
fi

if [[ "${pm}" == apt ]]; then
  dpkg -i "${pkg_file}" > /dev/null
  auth=/etc/apt/auth.conf.d/apt-puppetcore-puppet.conf
  mkdir -p "$(dirname "${auth}")"
  (umask 077 && awk 'BEGIN { printf "machine apt-puppetcore.puppet.com\nlogin forge-key\npassword %s\n", ENVIRON["PUPPET_FORGE_TOKEN"] }' > "${auth}")
  chmod 600 "${auth}"
  apt-get update -qq
  if ! apt-cache madison puppet-agent | grep -qF "${AGENT_VERSION}-1${REPO_ID}"; then
    skip "puppet-agent ${AGENT_VERSION} not published for ${REPO_ID}"
  fi
  apt-get install -y -qq "puppet-agent=${AGENT_VERSION}-1${REPO_ID}" > /dev/null
else
  rpm -i "${pkg_file}"
  repo="/etc/yum.repos.d/puppet${AGENT_MAJOR}-release.repo"
  (umask 077 && awk '
    /^#?username=/ { print "username=forge-key"; next }
    /^#?password=/ { print "password=" ENVIRON["PUPPET_FORGE_TOKEN"]; next }
    { print }
  ' "${repo}" > "${work}/repo.new")
  cat "${work}/repo.new" > "${repo}"
  chmod 600 "${repo}"
  if [[ "${pm}" == dnf ]]; then
    dnf makecache -q
    listing="$(dnf --showduplicates list puppet-agent 2> /dev/null || true)"
  else
    yum makecache -q
    listing="$(yum --showduplicates list puppet-agent 2> /dev/null || true)"
  fi
  if ! grep -qF "${AGENT_VERSION}" <<< "${listing}"; then
    skip "puppet-agent ${AGENT_VERSION} not published for ${REPO_ID}"
  fi
  "${pm}" install -y -q "puppet-agent-${AGENT_VERSION}" > /dev/null
fi

actual="$("${facter_bin}" --version | tr -d '[:space:]')"
if [[ "${actual}" != "${FACTER_VERSION}" ]]; then
  echo "facter ${actual} != ${FACTER_VERSION}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
/opt/puppetlabs/bin/facter -j > "${OUT_DIR}/facts.json"
write_result gathered ""
