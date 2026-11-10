# Audit: {slug}

- **Status**: {Open|Resolved} · **Base**: `{base_sha}` · **Head**: `{head_sha}` · **Date**: {YYYY-MM-DD}
- **Isolation**: {subagent | in-session (not independent)} · **Reviews**: {code[, safety]}
- **Flags**: `law1={true|false}` · `hotpath={true|false}` · `abi={true|false}`

## Gates
| Check | Result |
| :-- | :-- |
| `{commands.validate}` | {pass · fmt, clippy, check-no-std, cargo test, verify-specs · known baseline failures: n} |
| `vrka-check scan` | {0 BLOCK, n WARN, n WAIVED · waivers: none} |
| `vrka-check lock` | {pass} |
| `vrka-check skipped` | {pass} |
| `vrka-check covered` | {S-01..S-0n passing in `{report_file}`} |

## Findings
| ID | P | Source | file:line | Rule | Issue | Resolution |
| :-- | :-: | :-- | :-- | :-- | :-- | :-- |
| F-01 | P0 | safety | `crates/…:42` | RT-03 | {…} | R-01 ({sha}) |
| F-02 | P2 | code | `crates/…:10` | RT-11 | {…} | followup |

## Sync
- system_overview: {updated · no change} · domain_map: {…} · integration_map: {…} · `.sync` → `{sha}`
- ADRs → Validated: {list}

## Ship
- PR: {#n link} · CI: {green after n rounds} · Follow-ups: {list or none}
