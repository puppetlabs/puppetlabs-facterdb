# Changelog

## Unreleased

- Add fact-store tooling: `facts:validate`, `facts:normalise` and `facts:seed` rake tasks.
- Add the `config/scrub.yml` scrub policy and `config/facts.yml` filename and seed rules.
- Add a CI `facts` validation job.
- Add a `NOTICE` file crediting voxpupuli/facterdb and the facterdb-private fork, and ship it in the gem.

### 0.1.0

- Add the `puppetlabs-facterdb` gem (`require 'puppetlabs/facterdb'`, `Puppetlabs::FacterDB`).
- Add the lookup API (`Puppetlabs::FacterDB.get_facts` and helpers), ported from facterdb.
- Add the `puppetlabs-facterdb` CLI, printing matching facts as a JSON array.
- Add the `PUPPETLABS_FACTERDB_SEARCH_EXTERNAL_DIR`, `PUPPETLABS_FACTERDB_SKIP_DEFAULTDB` and `PUPPETLABS_FACTERDB_INJECT_SOURCE` environment variables.
