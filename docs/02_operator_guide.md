# Using Bolt — guide for the client's team

Open the **Bolt Console** tile. The screen has two sides:

- **Left — the process**, three tabs in the order you work: **1 Smart Forms → 2 Drafts → 3 Migrations**.
- **Right — Setup and Help.** The *Setup* card shows whether everything is ready (SAP system,
  GitHub connection, target repository, AI provider, driver index, administrators) and the
  **LIVE** pill when Bolt can send to GitHub. *Open setup* opens the Setup page (administrators).
  *Open help* opens the full in-app help (searchable) — it always describes the installed version.

The same help is in the app: `app/bolt-fiori/webapp/help/help.html`. Keep the two in step.

## 1. Choose the Smart Forms to migrate — *1 Smart Forms*

- Every custom Smart Form of this system is listed, with package, *Printed by* (driver programs and
  output types) and last change. Filter with the counts (*All, Can be selected, In migration,
  Stopped, Completed*) and search.
- Tick the forms → **Next (n)** → check the list → **Commit**.
- Each form gets the next **serial number** and its own GitHub branch. Its legacy files are produced
  in SAP and sent automatically — the dialog shows the result per form. Nothing has to be
  downloaded or uploaded.
- **GitHub not ready?** (not connected, no repository, no push access) — you can still commit: the
  button reads **Save as drafts** and the forms wait on the *Drafts* tab with their serial numbers.
- A form **in migration** or **completed** cannot be ticked (ticking several shows one summary of
  what was left out). A **stopped** form can: that starts a **re-process run** — new serial number,
  new branch, freshly produced files; the stopped run is closed.
- *Export* saves the list to a spreadsheet.

## 2. Send what has not reached GitHub — *2 Drafts*

- A draft = committed, but its initial load (legacy files + status file) is not on GitHub yet:
  saved while GitHub was not ready, or the send failed (certificate, network, proxy, GitHub
  refused, form locked). *Last attempt* shows the reason and the number of attempts.
- **Send to GitHub** (one row) or **Send all drafts** — repeat as often as needed, there is no
  limit when you send by hand. A sent draft moves to *3 Migrations*.
- **Discard** (bin) — the draft leaves the list and the form can be selected again (kept as stopped
  for the history; nothing was on GitHub).
- The background job `ZABR_BOLT_SYNC` retries drafts every 15 minutes once GitHub is set up, up to
  *Maximum send attempts* (default 5) per draft.

## 3. Follow the migrations — *3 Migrations*

- One row per migration on GitHub: serial number, form, branch, status, who it is waiting on (and
  the engineer window), complexity, last status change and age.
- Filters with counts: **Needs me** (waiting for your action — highlighted), *In progress, Stopped,
  Completed*. *Show replaced runs* adds the runs closed by a re-process.
- **Read statuses** reads every open migration from GitHub now (the background job does it every
  15 minutes anyway). *Export* saves the list.

## 4. Work on one migration — click a row

- A **draft** shows the reason it is not on GitHub yet with **Send to GitHub** / **Discard draft**.
  Legacy documents and the communication panel appear once it is on GitHub.
- **Migration status** shows the status file the engineer keeps on the branch, newest entry first.
- **Waiting on: client** — do what the note says, then:
  - **I've done this — confirm** (a note is optional). Only this lets the engineer continue.
  - or **Report a problem / Ask a question / Request a change** (type a note or attach files).
- **Raise a concern** — any time, also after completion.
- Files: drag them onto the box or *Choose files*; remove any before sending.
- **Stop this migration** (with a reason) pauses all work; **Resume migration** continues exactly
  where it was. To start over instead, select the form again on the Smart Forms tab.
- **Legacy documents** — add more reference files, or take files off the list (the branch keeps
  them), then **Save changes**.
- **Status history** — every event with date, user and status, kept in SAP.
- **AI summary** — a plain-language summary of the form from its legacy grab.

## 5. Setup (administrators)

*Open setup* on the right. See `04_installation.md` part D. Only users listed under
*Administrators* can change it; everybody can see it.
