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
- The bundled data covers Facter 4.0-4.11, seeded from facterdb-private (see [facts/PROVENANCE.md](facts/PROVENANCE.md)). Facter 4.12+ arrives from Puppet Core gathers.
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
bundle exec rake 'facts:seed[/path/to/facterdb-private]'       # import Facter 4.0-4.11 facts from a facterdb-private checkout
```

The scrub policy lives in `config/scrub.yml` and the filename and seed rules in `config/facts.yml`. The tooling under `tools/` is not shipped in the gem.

## Licence and attribution

Apache-2.0. Derived from [voxpupuli/facterdb](https://github.com/voxpupuli/facterdb) (Apache-2.0). Spec fixtures are copied from facterdb. Seeded data comes from Puppet's facterdb-private fork of voxpupuli/facterdb.

See [NOTICE](NOTICE) for attribution and [facts/PROVENANCE.md](facts/PROVENANCE.md) for the seed source.
