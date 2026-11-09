# 0001: Consumer loading of puppetlabs-facterdb

## Status

Accepted, 2026-11-09.

## Context

PDK modules get `facterdb` through `pdk-templates` Gemfile entries (`facterdb ~> 3.0` for Ruby >= 3, see `config_defaults.yml`). `rspec-puppet-facts` does `require 'facterdb'` and calls `FacterDB.get_facts`. `puppetlabs-facterdb` ships under a different require path (`puppetlabs/facterdb`), constant (`Puppetlabs::FacterDB`) and environment variables (`PUPPETLABS_FACTERDB_*`), so it is not picked up by existing consumers automatically.

## Decision

- A Perforce fork of `rspec-puppet-facts` will swap `require 'facterdb'` for `require 'puppetlabs/facterdb'` and `FacterDB` for `Puppetlabs::FacterDB`.
- Afterwards, `pdk-templates` will be updated to depend on the fork.
- Both are separate follow-up tickets and out of scope for this gem.
- No compatibility shim, adapter, `lib/facterdb.rb` alias or top-level `FacterDB` constant ships in this gem.

## Consequences

- Until the fork ships, consumers can call `Puppetlabs::FacterDB` directly.
- Upstream `FACTERDB_*` environment variables do not configure this gem. The extra-paths variable is `PUPPETLABS_FACTERDB_SEARCH_EXTERNAL_DIR`, not a renamed `FACTERDB_SEARCH_PATHS`, which the fork must account for.
- Both gems can be installed side by side with no shared require path, constant, executable, environment variable or cache key.

## Required API surface

The fork needs the following from `lib/puppetlabs/facterdb.rb`:

- `Puppetlabs::FacterDB.database`
- `Puppetlabs::FacterDB.cleanup`
- `Puppetlabs::FacterDB.use_defaultdb?`
- `Puppetlabs::FacterDB.inject_source?`
- `Puppetlabs::FacterDB.default_fact_files`
- `Puppetlabs::FacterDB.external_fact_files`
- `Puppetlabs::FacterDB.facterdb_fact_files`
- `Puppetlabs::FacterDB.generate_filter_str`
- `Puppetlabs::FacterDB.valid_filters?`
- `Puppetlabs::FacterDB.get_facts(filter = nil, cache = true, symbolize_keys: true)`
- `Puppetlabs::FacterDB::Errors::InvalidFilter`

When `PUPPETLABS_FACTERDB_INJECT_SOURCE` is set, each fact set also carries the injected `_facterdb_filename` and `_facterdb_path` keys.
