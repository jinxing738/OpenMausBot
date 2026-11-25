# CEObot Source Baseline

CEObot is an independent downstream project based on
[OpenMausBot](https://github.com/milind-soni/OpenMausBot).

## Import provenance

- Upstream repository: `https://github.com/milind-soni/OpenMausBot`
- Pinned commit: `05c52ac54c690e7e600ace8d759f4e9975d14e74`
- Retrieval date: 2026-11-25
- Imported scope: complete repository, including source, tests, documentation,
  build configuration, desktop and mobile companion code, and bundled assets
- Integrity check: all 9,781 Git blob hashes match the upstream tree manifest

The imported commit is the reproducible baseline for CEObot. Later product
changes should be made as CEObot commits on the local branch rather than by
tracking an unreviewed moving branch.

## Independence and trademarks

CEObot is not affiliated with xAI, Grok, MausBot, OpenMausBot, or their owners.
The upstream project describes itself as an independent Grok Bot alternative;
it is not official xAI source code.

The Apache 2.0 license does not grant trademark rights. Before distributing a
commercial edition, CEObot must replace the OpenMausBot and MausBot names,
logos, mascot, application identifiers, deep-link schemes, release channels,
and other product branding with its own cleared branding.

## Licensing

The repository is Apache 2.0 except for `enterprise/`, which is
source-available under `enterprise/LICENSE`. Production use of that directory
requires a license issued by its copyright holder. Hosting it for third
parties, reselling it, or white-labelling it requires a partner agreement.

For an Apache-2.0-only edition, remove `enterprise/` together with any
integration specific to it, while retaining the upstream `LICENSE`, `NOTICE`,
`LICENSING.md`, third-party notices, and attribution required by the bundled
dependencies.

## Isolation from StaffMate

CEObot has no StaffMate runtime dependency, import, symlink, copied data,
credential, or Git remote. Its only source remote is the OpenMausBot upstream
repository above.
