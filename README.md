# puppetlabs-facterdb

A database of OS facts, stored and looked up under the real Facter version that produced them. It coexists with upstream `facterdb`: nothing is shared between the two gems.

## Installation

```ruby
gem 'puppetlabs-facterdb'
```

Requires Ruby >= 3.1.

## Usage

```ruby
require 'puppetlabs/facterdb'

# Hash: keys are ANDed
Puppetlabs::FacterDB.get_facts({ 'os.family' => 'Debian', facterversion: '/^4\.11/' })

# Array of Hashes: each Hash is ORed
Puppetlabs::FacterDB.get_facts([{ 'os.name' => 'Debian' }, { 'os.name' => 'Ubuntu' }])

# String: passed straight to jgrep
Puppetlabs::FacterDB.get_facts('os.family=RedHat and facterversion=/^4\.11/')
```

`get_facts(filter = nil, cache = true, symbolize_keys: true)` returns an Array of Hashes. `facterversion` accepts a regex; nested facts use dotted paths such as `os.family`.

## CLI

```shell
puppetlabs-facterdb 'os.family=Debian'
```

Prints a pretty-printed JSON array of the matching facts. When nothing matches it prints `[]` and exits 0.

## Environment variables

| Variable | Effect |
|----------|--------|
| `PUPPETLABS_FACTERDB_SEARCH_EXTERNAL_DIR` | Path-separator delimited list of extra directories searched for `*.facts` files. Nonexistent directories are silently ignored. Extra files take precedence over bundled ones. |
| `PUPPETLABS_FACTERDB_SKIP_DEFAULTDB` | If set to any value (including empty), the facts bundled with the gem are skipped. |
| `PUPPETLABS_FACTERDB_INJECT_SOURCE` | If set, `_facterdb_filename` and `_facterdb_path` are injected into each fact set. |

The upstream `FACTERDB_*` environment variables have no effect on this gem.

## Data layout

```
facts/<facter major.minor>/<os>-<release>-<arch>.facts
```

- Each file holds one full `facter -j` JSON object.
- The latest patch release for each major.minor overwrites the previous one; the exact patch is in the inner `facterversion` fact.
- The directory is organisational only. Filters match the inner facts, not the directory name.
- The bundled data covers Facter 4.0-4.11, seeded from facterdb-private (source commit in [facts/seed-manifest.json](facts/seed-manifest.json)). Facter 4.12+ arrives from Puppet Core gathers.
- Filenames must not contain spaces. A `-core` release suffix is allowed, and rolling distros listed in `config/facts.yml` use `<os>-<arch>`.

## Using alongside facterdb

`puppetlabs-facterdb` shares no require path, constant, executable, environment variable or cache key with `facterdb`, so both can be installed together. Existing consumers such as `rspec-puppet-facts` keep using `facterdb` until they are switched over; see [docs/decisions/0001-consumer-loading.md](docs/decisions/0001-consumer-loading.md).

## Development

```shell
bundle install
bundle exec rake spec
bundle exec rake rubocop
BUNDLE_GEMFILE=spec/integration/dual_install/Gemfile bundle exec rspec spec/integration/dual_install
```

Fact store tooling:

```shell
bundle exec rake facts:validate                                # validate every fact file (CI runs this)
bundle exec rake facts:normalise                               # scrub and normalise fact files in place
CHECK=1 bundle exec rake facts:normalise                       # report files that would change, exit non-zero
bundle exec rake gather:next_version                           # print the Facter version the next gather would pick
bundle exec rake versions:update                               # refresh config/facter_versions.yml (needs PUPPET_FORGE_TOKEN)
```

The scrub policy lives in `config/scrub.yml` and the filename rules in `config/facts.yml`. The tooling under `tools/` is not shipped in the gem.

## Gathering facts

Two manually dispatched workflows keep the store current:

1. `update-facter-versions` refreshes `config/facter_versions.yml` (Facter version to agent version) from the Puppet Core gem index and release notes, and opens a PR.
2. `gather-facts` gathers one Facter version per run: the oldest not yet gathered, or an `X.Y.Z` passed as the `version` input. It provisions every OS in `config/metadata.json` that the provisioning service offers as a VM with litmus, installs the mapped agent, runs `facter -j`, scrubs and normalises the output and opens one PR.

A version is "not yet gathered" when no stored file in that major.minor reports a `facterversion` >= it, so older patches are never re-gathered. Existing fact files are never deleted.

- The OS list is `config/metadata.json`. To add an OS, edit it; names must match puppet_litmus `matrix.json`.
- The litmus fixture modules (default branch unless a `ref` is set) are listed in `config/litmus_modules.yml`.
- Scrubbing uses `config/scrub.yml`; review its effect on every facts PR.
- PRs are opened with `GITHUB_TOKEN` and merged by hand. They do not trigger CI; close and reopen to run checks. The repo setting "Allow GitHub Actions to create and approve pull requests" must stay enabled.
- Failed legs are listed in the PR body with a short reason (provision service error or other) and turn the run red; the remaining legs still land.
- A leg whose OS has no package for the mapped agent version is skipped, not failed: it exits green, does not turn the run red and is listed under "Skipped (no agent package for this OS)" in the PR body.
- Failure details from provisioning and agent install are withheld from the public run log (only a category is printed) because litmus output includes the VM address.
- The Puppet Core token comes from the org secret. It is set only on the steps that need it (the Bundler install steps, the matrix generator and the gather leg), and the gather workflows never run on pull requests.

Facts are gathered on provisioning service VMs only. Docker is not used because containers share the runner kernel and have no init, so `virtual`, `service_provider`, `kernel*` and similar facts would be wrong for the OS.

Known gaps: macOS, ppc64le and ARMv7L are not gathered. Fedora 41, AlmaLinux 10, Rocky 10 and Windows 11 have no litmus provisioner. AmazonLinux 2023, OracleLinux 8 and Ubuntu 26.04 are only available as docker and are not gathered.

## Licence and attribution

Apache-2.0. Derived from [voxpupuli/facterdb](https://github.com/voxpupuli/facterdb) (Apache-2.0). Spec fixtures are copied from facterdb. Seeded data comes from Puppet's facterdb-private fork of voxpupuli/facterdb.

See [NOTICE](NOTICE) for attribution and [facts/seed-manifest.json](facts/seed-manifest.json) for the seed source.
