# Connecting your SAP system to GitHub — what we need from you

**For:** the client's SAP Basis, network and security teams
**From:** Vernasoft
**About:** Bolt with Fiori, the Smart Form → Adobe Form migration app that runs in your SAP system

---

## Why the connection is needed

In Bolt with Fiori, your team selects Smart Forms on one screen and presses **Commit**. For each form,
your SAP system:

1. reads the form's definition, its driver program source and its output configuration (the
   "legacy grab"), and
2. sends these files to the GitHub repository Vernasoft keeps for your migrations, on a new branch
   per form.

Vernasoft's engineers build the Adobe Form from those files. The progress of each migration is kept
in a small status file on that branch. Your SAP system reads it to show the live status, and writes
to it when your team confirms a step, reports a problem or stops a migration.

So the SAP system that runs the app (normally **DEV**) must be able to call **GitHub's API over
HTTPS**. Nothing calls into your SAP system from outside.

## What leaves your SAP system

| Sent | Not sent |
|---|---|
| Smart Form definitions (the same XML as SMARTFORMS → Utilities → Download) | Business documents, customer or vendor data, prices, transactions |
| Source code of the driver programs and their includes | Passwords, user lists, HR data |
| Output configuration of the form (NACE: output type, driver program) | Anything from forms you did not select |
| Usage counts per output type (how many outputs in the last 30 / 365 days — numbers only) | |
| The status messages your team types in the app | |

If your team switches on the optional **AI summary**, the form's legacy-grab text is also sent to
the AI provider you configure, and only when someone presses the button.

## Checklist

| # | What | Who | Done |
|---|---|---|---|
| 1 | Allow outbound HTTPS (port 443) from the SAP application servers to `api.github.com` | Network / firewall | ☐ |
| 2 | If outbound traffic must use a proxy, give us the proxy host, port and (if any) the user | Network | ☐ |
| 3 | Import the certificates of `api.github.com` into STRUST | Basis | ☐ |
| 4 | Create the SM59 destination `ZBOLT_GITHUB` (we supply the token) | Basis | ☐ |
| 5 | Only for reading Smart Forms from QA/PRD: an HTTP destination from DEV to each of them, plus a technical user | Basis / security | ☐ |
| 6 | Roles for the people who use the app | Security | ☐ |
| 7 | Optional: outbound HTTPS to your AI provider + SM59 destination `ZBOLT_AI` | Network / Basis | ☐ |
| 8 | Run **Check access** in the app (Configuration tab) and send us a screenshot | Your app administrator | ☐ |

### 1. Network

- Destination host: **`api.github.com`**, port **443** (HTTPS), from **every application server** of
  the system that runs Bolt with Fiori (the ICM makes the call, not the user's PC).
- GitHub does not publish a fixed IP range for its API. Allow the host name; IP-based rules break
  without notice.
- Only `api.github.com` is needed. `github.com`, raw content and package hosts are not.

### 2. Proxy (only if you use one)

Tell us the proxy host and port, and a proxy user if one is needed. Basis enters them in the SM59
destination (tab *Logon & Security* → *HTTP Proxy Options*).

### 3. Certificates (STRUST)

1. Open `https://api.github.com` in a browser and look at the certificate chain. Export the **root**
   and **intermediate** certificates.
2. In STRUST, import both into the PSE **SSL client Standard** (or the PSE you use for outbound SSL),
   add them to the certificate list and save.
3. Restart the ICM (SMICM → Administration → ICM → Exit Soft) so it picks up the change.

Certificate authorities change from time to time. If **Check access** later reports an SSL error,
repeat this step with the current chain.

### 4. SM59 destination to GitHub — `ZBOLT_GITHUB`

| Field | Value |
|---|---|
| Connection type | **G** (HTTP connection to external server) |
| Host | `api.github.com` |
| Port / service | `443` |
| Path prefix | *(empty)* |
| Logon & Security → Logon procedure | **Basic authentication** |
| User | the GitHub account name we give you |
| Password | the **access token** we give you |
| SSL | **Active**, certificate list **SSL client Standard** (the PSE from step 3) |
| Proxy | as in step 2, if any |

**About the token.** Vernasoft creates a *fine-grained personal access token* that can see **only your
migration repository**, with the permission *Contents: read and write*. It cannot create
repositories, cannot see our other clients and cannot change settings. It expires after at most
12 months, and we send a new one before it does. We pass it to your Basis team through a channel you
choose (never by plain e-mail). It is stored only in the SM59 destination. The app never displays
it, writes it to logs or sends it anywhere except GitHub.

### 5. Reading Smart Forms from QA or PRD (optional)

The app can list and extract Smart Forms from **DEV, QA or PRD**. The user picks the system on the
Smart Forms Overview. The extraction always runs on the system that holds the form.

- Transport the Bolt with Fiori package (`ZBOLT_FIORI`) to QA/PRD and publish its service there
  (see the installation guide). The Fiori screen itself is only used in DEV.
- In **DEV**, create an HTTP destination per source system, for example `ZBOLT_QA` and `ZBOLT_PRD`:
  type **G** or **H**, the system's host and HTTPS port, SSL active, and logon with a
  **technical user** of that system.
- That technical user needs only to call the Bolt OData service (S_SERVICE for service group
  `ZBOLT_UI_O4`) and display authorization for Smart Forms and programs. It reads, and never
  changes anything.

### 6. Roles

| Role | Who | Contains |
|---|---|---|
| Bolt operator | people who select forms and answer the engineer | Launchpad tile / app `ZBOLT_FIORI`, S_SERVICE for `ZBOLT_UI_O4` |
| Bolt administrator | 1–2 people | same; their SAP user names are also entered under *Configuration → Administrators* |

Administrators change connections, add or remove source systems and withdraw migrations. If the
administrator list is left blank, every app user can do this.

### 7. AI provider (optional)

Only if you want the *AI summary* button: outbound HTTPS to your provider (`api.openai.com`,
`api.anthropic.com`, or your company's AI gateway), certificates as in step 3, and an SM59
destination `ZBOLT_AI` (type G, host of the provider, port 443, SSL active, no logon). The API key is
entered once in the app by an administrator. It is stored in a restricted table and never shown
again.

### 8. Check access

Open the app → **Configuration** → *GitHub* → **Check access**. Success reads like:

> Connected as … : VernasoftTechie/<your repository> (default branch main), write access confirmed.

| Message | Meaning |
|---|---|
| *SM59 destination ZBOLT_GITHUB cannot be used: it does not exist in SM59* | Step 4 not done, or a different name was typed in Configuration |
| *Call through SM59 destination … failed: SSL handshake …* | Step 3 (certificates) |
| *… failed: connection refused / timed out* | Step 1 or 2 (firewall, proxy) |
| *GitHub refused … (HTTP 401)* | Token wrong or expired — ask us for a new one |
| *GitHub refused … (HTTP 404)* | Token cannot see the repository — tell us |

Send us a screenshot of the result. We confirm from our side, and you can start selecting forms.

---

*Questions: contact your Vernasoft project lead. This page is the client-facing part of the
installation guide (`docs/04_installation.md`).*
