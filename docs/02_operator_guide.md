# Using Bolt — guide for the client's team

Open the **Bolt Console** tile. The header shows the SAP system and client the app runs in, and
three indicators: **GitHub**, **AI** and **LIVE**. New migrations can be committed only when LIVE is
green; if not, an administrator completes the Configuration tab.

## 1. Choose the Smart Forms to migrate — *Smart Forms* tab

- Every custom Smart Form of this system is listed, with package, driver programs, output types and
  last change. Search and filter (*Can be selected, In migration, Stopped, Completed*).
- Tick the forms to migrate → **Next** → check the list → **Commit**.
- Each form gets the next **serial number** and its own GitHub branch. Its legacy files are produced
  in SAP and sent automatically — the dialog shows the result per form. Nothing has to be
  downloaded or uploaded.
- A form **in migration** or **completed** cannot be selected again. A **stopped** form can: that
  starts a **re-process run** — new serial number, new branch, freshly produced files; the stopped
  run is closed.
- *Export* saves the list to a spreadsheet.

## 2. Follow the migrations — *Migration* tab

- One row per migration: serial number, form, run, status, who it is waiting on, the engineer
  window working on it, complexity, age, last status change. The KPI tiles above count them.
- **Needs me** shows the migrations waiting for your action (highlighted).
- **Read statuses** reads every open migration from GitHub now (the background job does it every
  15 minutes anyway). *Export* saves the list.

## 3. Work on one migration — click a row

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

## 4. Configuration (administrators)

See `04_installation.md` part D. Only users listed under *Administrators* can change it.
