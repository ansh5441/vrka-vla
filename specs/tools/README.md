# TLA+ Tools Directory (`specs/tools/`)

Place `tla2tools.jar` at `specs/tools/tla2tools.jar` (or set `TLA2TOOLS_JAR` in your environment).
`scripts/verify_specs.sh` invokes `pcal.trans` (when PlusCal blocks are present) and `tlc2.TLC`
against all `.tla` modules under `specs/`.
