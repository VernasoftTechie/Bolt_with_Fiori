# Build issues log

Every activation, runtime or deployment error hit on this repository, with its root cause and the
fix. Add an entry the moment a new one is hit. Use the same format as the other Vernasoft repos:
the situation, then the resolution.

| # | Date | Object | Symptom (exact message) | Root cause | Fix | Commit |
|---|---|---|---|---|---|---|
| B1 | 2026-11-18 | Dashboard.view.xml | Form selection lost when the commit dialog opened | `sap.m.Table` `rememberSelections` (default on) re-applied its own selection over the bound `selected` property on model refresh | `rememberSelections="false"` | initial |
| B2 | 2026-11-18 | Dashboard.view.xml | LIVE pill without colour | `class="{= ... }"` — CSS classes cannot be bound in XML views | inverted `ObjectStatus` with bound `state` | initial |
