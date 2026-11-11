#!/usr/bin/env bash
# Gather Facter facts on a hosted macOS runner by installing a pinned Puppet Core puppet-agent DMG
# from artifacts-puppetcore.puppet.com.
#
# Env: PUPPET_FORGE_TOKEN (secret), FACTER_VERSION, AGENT_VERSION, AGENT_MAJOR, PLATFORM_ID, OUT_DIR.
# Exit: 0 and OUT_DIR/result.json for gathered (plus facts.json) or skipped (HTTP 404, no package);
#       non-zero for bad input (2) or any credential, network, install or version error.
# The token reaches curl through a config on a process-substitution descriptor built with the printf
# builtin, so it is never in argv, logged or written to OUT_DIR.
# NOTE: the os_version/os_arch query values are confirmed in the 03-07 spike (research A4).
set -euo pipefail

for name in PUPPET_FORGE_TOKEN FACTER_VERSION AGENT_VERSION AGENT_MAJOR PLATFORM_ID OUT_DIR; do
  if [[ -z "${!name:-}" ]]; then
    echo "missing required env var: ${name}" >&2
    exit 2
  fi
done

if [[ ! "${FACTER_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  [[ ! "${AGENT_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
  [[ ! "${AGENT_MAJOR}" =~ ^[0-9]+$ ]] ||
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

os_version="$(sw_vers -productVersion | cut -d. -f1)"
case "$(uname -m)" in
  arm64 | aarch64) os_arch=arm64 ;;
  x86_64) os_arch=x86_64 ;;
  *)
    echo "unsupported architecture" >&2
    exit 1
    ;;
esac

work="$(mktemp -d)"
mnt=""
cleanup() {
  if [[ -n "${mnt}" ]]; then
    hdiutil detach "${mnt}" -quiet || true
  fi
  rm -rf "${work}"
}
trap cleanup EXIT

dmg="${work}/puppet-agent.dmg"
url="https://artifacts-puppetcore.puppet.com/v1/download?type=native&version=${AGENT_VERSION}&os_name=osx&os_version=${os_version}&os_arch=${os_arch}&fips=false"

status="$(curl -sS -L -o "${dmg}" -w '%{http_code}' -K <(printf 'user = "forge-key:%s"\n' "${PUPPET_FORGE_TOKEN}") "${url}")"
if [[ "${status}" == 404 ]]; then
  skip "puppet-agent ${AGENT_VERSION} not published for macOS ${os_version} ${os_arch}"
elif [[ "${status}" != 200 ]]; then
  echo "agent download failed with HTTP ${status}" >&2
  exit 1
fi

mnt="${work}/mnt"
mkdir -p "${mnt}"
hdiutil attach -nobrowse -readonly -mountpoint "${mnt}" "${dmg}" > /dev/null
pkg="$(find "${mnt}" -maxdepth 1 -name '*.pkg' | head -n 1)"
if [[ -z "${pkg}" ]]; then
  echo "no .pkg found in the agent image" >&2
  exit 1
fi
sudo installer -pkg "${pkg}" -target / > /dev/null

actual="$("${facter_bin}" --version | tr -d '[:space:]')"
if [[ "${actual}" != "${FACTER_VERSION}" ]]; then
  echo "facter ${actual} != ${FACTER_VERSION}" >&2
  exit 1
fi

mkdir -p "${OUT_DIR}"
"${facter_bin}" -j > "${OUT_DIR}/facts.json"
write_result gathered ""
