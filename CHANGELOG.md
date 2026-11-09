# Changelog

## Unreleased

### 0.1.0

- Add the `perforce-facterdb` gem (`require 'perforce/facterdb'`, `Perforce::FacterDB`).
- Add the lookup API (`Perforce::FacterDB.get_facts` and helpers), ported from facterdb.
- Add the `perforce-facterdb` CLI, printing matching facts as a JSON array.
- Add the `PERFORCE_FACTERDB_SEARCH_EXTERNAL_DIR`, `PERFORCE_FACTERDB_SKIP_DEFAULTDB` and `PERFORCE_FACTERDB_INJECT_SOURCE` environment variables.
