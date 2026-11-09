# perforce-facterdb

A database of OS facts, stored and looked up under the real Facter version that produced them. It coexists with upstream `facterdb`: nothing is shared between the two gems.

## Installation

```ruby
gem 'perforce-facterdb'
```

Requires Ruby >= 3.1.

## Usage

```ruby
require 'perforce/facterdb'

# Hash: keys are ANDed
Perforce::FacterDB.get_facts({ 'os.family' => 'Debian', facterversion: '/^4\.11/' })

# Array of Hashes: each Hash is ORed
Perforce::FacterDB.get_facts([{ 'os.name' => 'Debian' }, { 'os.name' => 'Ubuntu' }])

# String: passed straight to jgrep
Perforce::FacterDB.get_facts('os.family=RedHat and facterversion=/^4\.11/')
```

`get_facts(filter = nil, cache = true, symbolize_keys: true)` returns an Array of Hashes. `facterversion` accepts a regex; nested facts use dotted paths such as `os.family`.

## CLI

```shell
perforce-facterdb 'os.family=Debian'
```

Prints a pretty-printed JSON array of the matching facts. When nothing matches it prints `[]` and exits 0.

## Environment variables

| Variable | Effect |
|----------|--------|
| `PERFORCE_FACTERDB_SEARCH_EXTERNAL_DIR` | Path-separator delimited list of extra directories searched for `*.facts` files. Nonexistent directories are silently ignored. Extra files take precedence over bundled ones. |
| `PERFORCE_FACTERDB_SKIP_DEFAULTDB` | If set to any value (including empty), the facts bundled with the gem are skipped. |
| `PERFORCE_FACTERDB_INJECT_SOURCE` | If set, `_facterdb_filename` and `_facterdb_path` are injected into each fact set. |

The upstream `FACTERDB_*` environment variables have no effect on this gem.

## Data layout

```
facts/<facter major.minor>/<os>-<release>-<arch>.facts
```

- Each file holds one full `facter -j` JSON object.
- The latest patch release for each major.minor overwrites the previous one; the exact patch is in the inner `facterversion` fact.
- The directory is organisational only. Filters match the inner facts, not the directory name.
- The bundled `facts/` directory is empty until data is seeded.

## Using alongside facterdb

`perforce-facterdb` shares no require path, constant, executable, environment variable or cache key with `facterdb`, so both can be installed together. Existing consumers such as `rspec-puppet-facts` keep using `facterdb` until they are switched over; see [docs/decisions/0001-consumer-loading.md](docs/decisions/0001-consumer-loading.md).

## Development

```shell
bundle install
bundle exec rake spec
bundle exec rake rubocop
BUNDLE_GEMFILE=spec/dual_install/Gemfile bundle exec rspec spec/dual_install
```

## Licence and attribution

Apache-2.0. Derived from [voxpupuli/facterdb](https://github.com/voxpupuli/facterdb) (Apache-2.0). Spec fixtures are copied from facterdb.
