# Connecting your SAP system to GitHub — what we need from you

**For:** the client's SAP Basis, network and security teams
**From:** Vernasoft
**About:** Bolt, the Smart Form → Adobe Form migration app that runs in your SAP system (Fiori)

---

## Why the connection is needed

In Bolt your team selects Smart Forms on one screen and presses **Commit**. For each form, your SAP
system — the one the app runs in:

1. produces the form's legacy files itself: the form definition (the same XML as SMARTFORMS →
   Utilities → Download), the Smart Styles it uses, the driver program sources and the output
   configuration (the "legacy grab"), and
2. sends them to your migration repository on GitHub, on a new branch per form.

Vernasoft's engineers build the Adobe Form from those files. The progress of each migration is kept
in a small status file on that branch. Your SAP system reads it to show the live status, and writes
to it when your team confirms a step, reports a problem or stops a migration.

So the SAP system that runs the app (normally **DEV**) must be able to call **GitHub's API over
HTTPS**. Nothing calls into your SAP system from outside.

## What leaves your SAP system

| Sent | Not sent |
|---|---|
| Smart Form and Smart Style definitions of the forms you select | Business documents, customer or vendor data, prices, transactions |
| Source code of their driver programs and includes | Passwords, user lists, HR data |
| Output configuration (NACE: output type, driver program) | Anything from forms you did not select |
| Usage counts per output type (numbers only) | |
| The messages and files your team sends to the engineer in the app | |

If you connect an **AI provider**, a form's legacy-grab text is sent to it only when someone presses
*AI summary* on that form. With the built-in provider nothing is sent anywhere.

## What is stored in your SAP system

The basic status of every migration (serial number, status, who it is waiting on, stop, dates,
files) and a status history — so your team can analyse progress at any time. The messages
themselves are not copied into SAP; they stay in the status file on the branch.

## Checklist

| # | What | Who | Done |
|---|---|---|---|
| 1 | Allow outbound HTTPS (443) from the SAP application servers to `api.github.com` | Network / firewall | ☐ |
| 2 | If outbound traffic must use a proxy: proxy settings in SICF (or an SM59 destination, see 6) | Network / Basis | ☐ |
| 3 | Import the certificates of `api.github.com` into STRUST (PSE *SSL client Anonymous*) | Basis | ☐ |
| 4 | A GitHub token for your migration repository (we create it with you) | Vernasoft + your admin | ☐ |
| 5 | Roles for the people who use the app; protect the secrets table | Security | ☐ |
| 6 | Optional: outbound HTTPS to your AI provider | Network | ☐ |
| 7 | **Check access** on the app's Configuration tab shows "push access"; send us a screenshot | Your Bolt administrator | ☐ |

### 1. Network

- Destination host **`api.github.com`**, port **443**, from **every application server** of the
  system that runs Bolt (the ICM makes the call, not the user's PC).
- GitHub does not publish a fixed IP range for its API — allow the host name.
- Only `api.github.com` is needed for the app. (abapGit, used once to install the app, also needs
  `github.com` — or the installation is done offline from a ZIP file.)

### 2. Proxy (only if you use one)

Enter the proxy in **SICF → Client → Proxy Settings** (HTTPS). If your policy needs a proxy only for
this connection, create an SM59 destination instead (type **G**, host `api.github.com`, port 443,
SSL active with *SSL client Anonymous*, the proxy on the *Logon & Security* tab, **no logon data**)
and give its name to your Bolt administrator — it goes into *Configuration → Advanced → GitHub SM59
destination*.

### 3. Certificates (STRUST)

1. Open `https://api.github.com` in a browser and export the **root** and **intermediate**
   certificates of the chain.
2. STRUST → PSE **SSL client Anonymous** → import both → *Add to Certificate List* → save.
3. SMICM → Administration → ICM → Exit Soft (the ICM re-reads the PSE).

Certificate authorities change from time to time. If *Check access* later reports an SSL error,
repeat this with the current chain. (If your Basis team uses another PSE for outbound SSL, enter its
SSL client ID under *Configuration → Advanced*.)

### 4. The GitHub token

- A **fine-grained personal access token** that can see **only your migration repository**, with
  the permission **Contents: Read and write**. It cannot see other repositories or change settings.
- It is pasted **once** on the app's Configuration tab by your Bolt administrator. The app checks
  it with GitHub, stores it in SAP (table `ZABT_BOLT_SECRT`, encoded) and never shows, logs or
  sends it anywhere except GitHub. *Disconnect* removes it.
- To let the app **create** the repository, the token also needs *Administration: Read and write*
  — or create the repository on GitHub yourself and only check access in the app.
- Tokens expire (at most 12 months for fine-grained tokens). Before that, paste a new one.

### 5. Roles and the secrets table

| Role | Who | Contains |
|---|---|---|
| Bolt user | people who select forms and answer the engineer | Launchpad tile of the app; S_SERVICE for the OData V4 service group `ZAB_UI_BOLT_O4` |
| Bolt administrator | 1–2 people | same role; their SAP user IDs are entered in the app under *Configuration → Administrators* |

Only administrators can change the Configuration tab (connections, repository, library). Restrict
**S_TABU_NAM** for table `ZABT_BOLT_SECRT` to Basis, so the stored token cannot be displayed in
SE16.

### 6. AI provider (optional)

Outbound HTTPS to `api.openai.com`, `api.anthropic.com` or your company's AI gateway, with its
certificates in the same PSE. The key is pasted on the Configuration tab and stored like the GitHub
token.

### 7. Check

The Bolt administrator opens *Configuration → 2. Repository → Check access*. Expected:
**"✓ owner/repository · private · default branch main · push access"**, and the header shows
**GitHub ✓ · AI ✓ · LIVE**.
