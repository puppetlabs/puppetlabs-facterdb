# Fact data provenance

The fact files under `facts/` were seeded by `rake facts:seed` from `https://github.com/puppetlabs/facterdb-private.git` at commit `883a32c168d14b512322e0f949ead07a7ebcb857` on 2026-11-10.
Facter range: 4.0-4.11. Source checkout had uncommitted changes: no.

| Result | Files |
| --- | --- |
| seeded | 368 |
| renamed | 3 |
| skipped | 0 |
| superseded | 0 |
| kept | 0 |

## Renamed

- `facts/4.2/windows-2012 r2-x86_64.facts` -> `windows-2012r2-x86_64.facts`
- `facts/4.3/windows-2012 r2-x86_64.facts` -> `windows-2012r2-x86_64.facts`
- `facts/4.4/windows-2012 r2-x86_64.facts` -> `windows-2012r2-x86_64.facts`

## Notes

Fact JSON is never annotated; provenance lives only in this file and `seed-manifest.json`. Fact files are scrubbed per `config/scrub.yml` and normalised before they are written.

## Attribution

This data derives from [voxpupuli/facterdb](https://github.com/voxpupuli/facterdb) (Apache-2.0) via Puppet's fork puppetlabs/facterdb-private. See [NOTICE](../NOTICE).
