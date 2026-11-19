# Operator Checklist — Smart Form → Adobe Form Migration

What the migration engineer will ask you to do, check and confirm on every form. The same steps repeat for each form, so this is the list to keep ready.

**Golden rules**
- Answer only through **Bolt Console** ("I've done this — confirm" or "Report a problem"). A message in chat does not release the next step.
- One step at a time. The engineer stops and waits after each request, so nothing moves until you confirm.
- If something fails, use **Report a problem** and paste the **exact SAP message** (a screenshot helps). Do not paraphrase.
- Always Stage, Commit and Push **both** objects (the interface `_INT` and the form `_ADT`) to the form's own branch.

---

## 1. When you raise a new migration
- [ ] Attach the Smart Form export (Utilities → Download XML) and any driver/print-program sources you have.
- [ ] If the form uses a **SmartStyle** (fonts/paragraphs), download it in SMARTSTYLES (Utilities → Download) and add it under "SmartStyle exports" in Configure. Without it the engineer can only use placeholder fonts (Arial).
- [ ] Be ready to say **which program or output type calls the form**. The engineer lists candidates but cannot confirm the driver, so please confirm it with the functional owner before go-live.

## 2. Interface step (in SAP)
- [ ] In **SFP**, create the interface `<FORM>_INT` and the form `<FORM>_ADT` in package **ZAB_ADOBE**. Keep the form **empty**, the safe starting point.
- [ ] In **abapGit**, Pull the form's branch onto that interface.
- [ ] Check the interface looks right:
  - Import/Export/Table parameters are present
  - Types and Global Data tabs are filled
  - The Initialization tab shows the legacy code
  - Any reference fields (currency/quantity) are listed
- [ ] **Do not drag anything into the form's Context yourself** unless the engineer says to. Dragging whole structures pulls in amount/quantity fields that then demand references.
- [ ] Stage, Commit and Push the interface **and** the empty form back to the same branch.
- [ ] Do not Pull over something you typed natively in SFP if it already matches. Push your state instead.
- [ ] Confirm in Bolt Console, or report the exact error.

## 3. Context step
- [ ] Pull the branch onto the form `<FORM>_ADT`.
- [ ] Check the Context tree shows the **node count the engineer states**, with all fields bound and **no deserialize error**.
- [ ] Imported clean → confirm. SAP error → Report a problem with the **exact message**.

## 4. Currency / quantity reference fields (only if SAP complains)
- [ ] Report each message exactly (for example "Reference field … cannot be used here").
- [ ] Decide and tell the engineer:
  - the **single document currency** field to use (usually a top-level currency parameter), or the real per-line currency field
  - the **exact field that holds the unit of measure** for each quantity field
- [ ] A reference must be a field inside the form's own interface or context. Database fields such as `VBRK-WAERK` are rejected.

## 5. Layout step
- [ ] Pull the branch onto `<FORM>_ADT` and **Activate**. Note the activation result.
- [ ] Open the **Layout** and report any warning or overflow badges.
- [ ] **Preview with real data:**
  - a normal document
  - a long document that runs past one page, if your documents can be long
  - a short document
- [ ] Check the header values, item rows, totals, labels, alignment and page breaks. On later pages, check the repeated title, header and column headings, and that no rows are missing.
- [ ] If you adjust anything in Designer, **push it back and tell the engineer**. Every Designer save is compared against the last version before more is built on it.
- [ ] Confirm that it looks right, or say which page and what you see (a screenshot helps).

## 6. Decisions only you or the business can give
- [ ] Fonts, sizes and alignment, if the SmartStyle was not supplied.
- [ ] Whether documents can run to **multiple pages**, so continuation is built and tested.
- [ ] Exact title/logo positions if the legacy offset must be matched.
- [ ] Any extra fields to print that the legacy form did not show (the engineer adds the matching currency/unit reference).
- [ ] Which program or output type will call the new Adobe form. The wiring is decided later, per driver, by that driver's owner.

## 7. Closing the form
- [ ] Final activation and preview confirmed in SAP.
- [ ] The business owner reviews it. High-risk forms need a **named** sign-off.
- [ ] Raise any follow-up change in Bolt Console. The form stays open to changes after sign-off.

## 8. Stop and problem controls
- [ ] Use **Stop** in Bolt Console to pause a migration. The engineer does nothing on it until it is released.
- [ ] If the SFP object starts behaving oddly (an unresponsive Layout, can't select or edit), tell the engineer. The usual fix is to delete and recreate the object from the last good branch state.
