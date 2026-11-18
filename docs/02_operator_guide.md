# Operator guide

What the client's operator does in Bolt with Fiori, from start to finish. It is the same process
as before, without downloading or uploading any legacy files.

## Golden rules

- Answer the engineer **only in the app**: *I've done this — confirm*, *Report a problem*, *Ask a
  question*, *Request a change*, *Raise a concern*. A chat message or e-mail does not release the
  next step.
- One step at a time. After each request the engineer stops and waits for your answer.
- When something fails, paste the **exact SAP message** (or attach a screenshot) when you report it.
- In abapGit, always Stage → Commit → Push **both** objects (interface `_INT` and form `_ADT`) to the
  migration's own branch.

## 1. Start migrations

1. **Smart Forms Overview** → choose the **source system** (DEV, QA, PRD).
2. Find the forms (search, or *Available* / *In migration*). A form already in migration shows its
   number and status and cannot be ticked again.
3. Tick the forms → **Next** → check the list → **Commit selection**.
4. Wait until every row says *Sent*. A row that says *Sending failed* is retried automatically, or
   open it in the Migration tab and press *Send to GitHub again*.

Before you start, ask your administrator to make sure the form's **SmartStyle** and the **driver
program** are known. Fonts are only exact when the style definition is available.

## 2. Follow your migrations

**Migration** tab — *Waiting on me* shows what needs you. Open a migration to see:

- the **status** and who it is waiting on
- the **note** with the exact request
- the full **activity** timeline from the branch

## 3. When it is waiting on you

Typical requests, in this order:

| Step | What you do in SAP | Then in the app |
|---|---|---|
| Interface | SFP: create the empty interface `<FORM>_INT` and form `<FORM>_ADT` in the agreed package. abapGit: pull the branch; check the parameters, types, global data and initialization code; push both objects back | Confirm, or report the exact error |
| Context | abapGit: pull; check the Context shows the number of nodes the engineer states and no deserialize error | Confirm, or report the exact error |
| Currency/quantity references (only if SAP complains) | Note every message exactly | Report a problem; say which currency/unit field to use |
| Layout | Pull, **Activate**, open the Layout (any warnings?), **Preview** with real data: normal, long (multi-page) and short documents | Confirm, or say which page looks wrong and attach a screenshot |
| Extra files | — | *Add a reference file*: the SFP migration wizard's form of the same Smart Form, a legacy printout PDF |

If you changed anything in Designer yourself, push it back and say so when you confirm.

## 4. Stop and follow-up

- **Stop this migration** pauses it. The engineer does nothing until you press **Resume**.
- **Raise a concern** is available at any time, also after completion.
- **AI summary** (if switched on) explains the form in plain language from its legacy grab.

## 5. Administrators only

- **Configuration:** connections (SAP systems, GitHub, AI), form prefixes, administrators.
- **Withdraw** (on a migration): the form can be selected again. Optionally the branch is deleted
  on GitHub, which is irreversible. Withdraw only if no SAP work depends on it.
- **Import from GitHub:** adds migrations that were started with the old web console.
