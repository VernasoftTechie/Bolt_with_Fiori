// Increment 1 (DDIC) generator: writes every domain (DOMA), data element (DTEL) and table (TABL)
// of Bolt with Fiori into src/ in the abapGit shapes proven on real systems
// (ZRAP_MT and Dangote_Requirements DOMA/DTEL, ZRAP_MT TABL - see docs/05_build_notes.md).
//
//   node tools/gen_ddic.mjs
//
// Naming follows "Policy for ABAP Naming Standards - DIL" (Ver 1.0), module ID AB (ABAP / non-functional):
//   domain        ZAB_DM_BOLT_<name>   max 30   (ZAA_B_ with B = DM)
//   data element  ZAB_DE_BOLT_<name>   max 30   (ZAA_B_ with B = DE)
//   table         ZABT_BOLT_<name>     max 16   (ZAAB_ with B = T)
//   table field   <name>               max 16
// Domain, data element and field carry the SAME descriptive name (one domain per data element).
// Generic technical fields use standard SAP data elements (SYSUUID_X16, TIMESTAMPL, SYUNAME, ...).
// All tables are cross-client (no MANDT): Smart Forms are cross-client repository objects, so one
// migration list per system is correct, whichever client the app is opened in.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = path.join(root, 'src');
const BOM = '﻿';
const pad = (n, w = 6) => String(n).padStart(w, '0');
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const problems = [];
const check = (ok, msg) => { if (!ok) problems.push(msg); };

// ---------------------------------------------------------------------------------------------
// Field catalog. type: C<n> (CHAR n), INT4, STRG.  lower: mixed case allowed.
// t: [short<=10, medium<=20, long<=40, description<=60]
// values: fixed values [value, text<=60]
// ---------------------------------------------------------------------------------------------
const F = {
  SETUP_ID: { type: 'C10', t: ['Setup', 'Setup ID', 'Setup ID', 'Bolt setup ID (always DEFAULT)'] },
  CUSTOMER_NAME: { type: 'C80', lower: true, t: ['Client', 'Client name', 'Client name shown in the app', 'Bolt client name shown in the app header'] },
  ADMIN_USERS: { type: 'C255', t: ['Admins', 'Administrators', 'Bolt administrators (SAP user IDs)', 'Bolt administrators, comma separated SAP user IDs'] },
  GH_API_URL: { type: 'C255', lower: true, t: ['GitHub API', 'GitHub API URL', 'GitHub API URL', 'Bolt GitHub API base URL (https://api.github.com)'] },
  SSL_ID: { type: 'C6', t: ['SSL ID', 'SSL client ID', 'SSL client identity (STRUST)', 'Bolt SSL client PSE for outbound HTTPS (ANONYM/DFAULT)'] },
  GH_REPO: { type: 'C140', lower: true, t: ['Repository', 'Target repository', 'Target repository (owner/name)', 'Bolt target GitHub repository owner/name'] },
  GH_BASE_BRANCH: { type: 'C120', lower: true, t: ['Default br', 'Default branch', 'Default branch of the repository', 'Bolt default branch of the target repository'] },
  GH_BRANCH_PFX: { type: 'C60', lower: true, t: ['Br. prefix', 'Branch prefix', 'Prefix of every migration branch', 'Bolt prefix of every migration branch'] },
  GH_PRIVATE: { type: 'BOOL', t: ['Private', 'Private repository', 'Repository is private', 'Bolt target repository is private'] },
  GH_CAN_PUSH: { type: 'BOOL', t: ['Can push', 'Push access', 'Token has push access', 'Bolt GitHub token has push access to the repository'] },
  GH_TOKEN_SET: { type: 'BOOL', t: ['Connected', 'GitHub connected', 'A GitHub token is stored', 'Bolt GitHub token is stored'] },
  GH_LOGIN: { type: 'C80', lower: true, t: ['Login', 'GitHub login', 'GitHub login of the token', 'Bolt GitHub login the token belongs to'] },
  GH_USER_NAME: { type: 'C80', lower: true, t: ['Name', 'GitHub name', 'GitHub display name', 'Bolt GitHub display name of the token owner'] },
  GH_SCOPES: { type: 'C255', lower: true, t: ['Scopes', 'Token scopes', 'Token scopes reported by GitHub', 'Bolt GitHub token scopes (classic tokens only)'] },
  GH_CONNECTED_AT: { type: 'TS', t: ['Connected', 'Connected at', 'GitHub connected at', 'Bolt GitHub token connected at'] },
  GH_CHECK_RES: { type: 'C10', values: [['OK', 'Check passed'], ['ERROR', 'Check failed']], t: ['Repo check', 'Repository check', 'Result of the repository check', 'Bolt result of the last repository access check'] },
  GH_CHECK_MSG: { type: 'C255', lower: true, t: ['Message', 'Repository message', 'Message of the repository check', 'Bolt message of the last repository access check'] },
  GH_CHECKED_AT: { type: 'TS', t: ['Checked', 'Repo checked at', 'Repository checked at', 'Bolt repository access checked at'] },
  STATUS_FOLDER: { type: 'C120', lower: true, t: ['Status dir', 'Status folder', 'Folder of the status files', 'Bolt repository folder of the status files'] },
  LIB_FOLDER: { type: 'C120', lower: true, t: ['Library', 'Library folder', 'Folder of the global reference library', 'Bolt repository folder of the global reference library'] },
  AI_PROVIDER: {
    type: 'C20', lower: true,
    values: [['mock', 'Built-in (offline, no key)'], ['openai', 'OpenAI (or compatible gateway)'], ['anthropic', 'Anthropic']],
    t: ['Provider', 'AI provider', 'AI provider', 'Bolt AI provider'],
  },
  AI_MODEL: { type: 'C80', lower: true, t: ['Model', 'AI model', 'AI model name', 'Bolt AI model name'] },
  AI_BASE_URL: { type: 'C255', lower: true, t: ['Base URL', 'AI base URL', 'AI base URL (blank = provider default)', 'Bolt AI base URL (blank = provider default)'] },
  AI_MAX_TOKENS: { type: 'INT4', t: ['Max tokens', 'Max tokens', 'Maximum response tokens', 'Bolt AI maximum response tokens'] },
  AI_KEY_SET: { type: 'BOOL', t: ['Key saved', 'AI key saved', 'An AI API key is stored', 'Bolt AI API key is stored'] },
  AI_CHECK_RES: { type: 'C10', values: [['OK', 'Check passed'], ['ERROR', 'Check failed']], t: ['AI check', 'AI check', 'Result of the AI connection test', 'Bolt result of the last AI connection test'] },
  AI_CHECK_MSG: { type: 'C255', lower: true, t: ['Message', 'AI message', 'Message of the AI connection test', 'Bolt message of the last AI connection test'] },
  AI_CHECKED_AT: { type: 'TS', t: ['Tested', 'AI tested at', 'AI connection tested at', 'Bolt AI connection tested at'] },
  FORM_PREFIXES: { type: 'C60', t: ['Prefixes', 'Form name prefixes', 'Custom Smart Form prefixes (Z,Y)', 'Bolt custom Smart Form name prefixes, comma separated'] },
  COUNT_VOLUME: { type: 'BOOL', t: ['Volume', 'Count volume', 'Count output volume (NAST)', 'Bolt count output volume from NAST in the legacy grab'] },

  SERIAL_NO: { type: 'INT4', t: ['Serial', 'Serial no.', 'Serial number', 'Bolt migration serial number'] },
  RUN_NO: { type: 'INT4', t: ['Run', 'Run no.', 'Run number (1 = first, 2+ = re-process)', 'Bolt migration run number of the form'] },
  FORM_DESCR: { type: 'C80', lower: true, t: ['Descr.', 'Description', 'Smart Form description', 'Bolt Smart Form description'] },
  DRIVER_PROGS: { type: 'C255', t: ['Drivers', 'Driver programs', 'Driver programs (comma separated)', 'Bolt driver programs of the Smart Form'] },
  OUTPUT_TYPES: { type: 'C255', t: ['Out. types', 'Output types', 'Output types (comma separated)', 'Bolt output types that print the Smart Form'] },
  BRANCH_NAME: { type: 'C120', lower: true, t: ['Branch', 'Branch', 'GitHub branch of the migration', 'Bolt GitHub branch of the migration'] },
  FORM_SLUG: { type: 'C60', lower: true, t: ['Slug', 'File slug', 'File-name slug of the form', 'Bolt file-name slug of the form'] },
  PUSH_STATUS: {
    type: 'C10',
    values: [['PENDING', 'Not sent to GitHub yet'], ['PUSHED', 'Sent to GitHub'], ['FAILED', 'Sending to GitHub failed']],
    t: ['GitHub', 'Sent to GitHub', 'Sent to GitHub', 'Bolt status of the transfer to GitHub'],
  },
  PUSH_MSG: { type: 'C255', lower: true, t: ['Message', 'Transfer message', 'Message of the last transfer', 'Bolt message of the last transfer to GitHub'] },
  PUSH_ATTEMPTS: { type: 'INT4', t: ['Attempts', 'Transfer attempts', 'Transfer attempts', 'Bolt number of transfer attempts to GitHub'] },
  FILES_COUNT: { type: 'INT4', t: ['Files', 'Files', 'Files on the branch', 'Bolt number of files on the migration branch'] },
  COMMIT_SHA: { type: 'C40', lower: true, t: ['Commit', 'Commit', 'Git commit SHA', 'Bolt Git commit SHA'] },
  MIG_STATUS: {
    type: 'C30', lower: true,
    values: [
      ['queued', 'Queued'], ['in_progress', 'In Progress'], ['interface_completed', 'Interface Completed'],
      ['waiting_manual', 'Waiting - Manual Activity'], ['layout_in_progress', 'Form Design In Progress'],
      ['completed', 'Migration Completed'], ['open_for_concerns', 'Open - Awaiting Review'],
    ],
    t: ['Status', 'Status', 'Status from the branch status file', 'Bolt migration status from the branch status file'],
  },
  WAITING_ON: { type: 'C30', lower: true, t: ['Waiting on', 'Waiting on', 'Waiting on (engineer/client)', 'Bolt migration waiting on (from the status file)'] },
  STOPPED: { type: 'BOOL', t: ['Stopped', 'Stopped', 'Stop requested', 'Bolt migration stop requested'] },
  SUPERSEDED: { type: 'BOOL', t: ['Superseded', 'Superseded', 'Replaced by a re-process run', 'Bolt migration replaced by a re-process run'] },
  CLAIMED_BY: { type: 'C80', lower: true, t: ['Picked up', 'Picked up by', 'Engineer window working on it', 'Bolt engineer window working on the migration'] },
  STATUS_UPDATED: { type: 'C30', lower: true, t: ['Updated', 'Status updated', 'UPDATED value of the status file', 'Bolt UPDATED value of the status file (ISO time)'] },
  STATUS_SHA: { type: 'C40', lower: true, t: ['File SHA', 'Status file SHA', 'Blob SHA of the status file', 'Bolt blob SHA of the status file read last'] },
  COMPLEXITY: {
    type: 'C10', lower: true,
    values: [['low', 'Low'], ['medium', 'Medium'], ['high', 'High']],
    t: ['Complexity', 'Complexity', 'Complexity signal', 'Bolt Smart Form complexity signal'],
  },
  COMPLEXITY_INFO: { type: 'C255', lower: true, t: ['Signal', 'Complexity detail', 'What the complexity signal counted', 'Bolt detail of the Smart Form complexity signal'] },
  HIST_EVENT: {
    type: 'C20',
    values: [
      ['COMMITTED', 'Selected for migration'], ['PUSHED', 'Sent to GitHub'], ['PUSH_FAILED', 'Sending to GitHub failed'],
      ['STATUS', 'Status changed on the branch'], ['CONFIRMED', 'Manual activity confirmed'], ['PROBLEM', 'Problem reported'],
      ['QUESTION', 'Question asked'], ['CHANGE', 'Change requested'], ['CONCERN', 'Concern raised'],
      ['STOPPED', 'Stop requested'], ['RESUMED', 'Resumed'], ['DOCS_ADDED', 'Legacy documents added'],
      ['DOCS_REMOVED', 'Legacy documents removed from the list'], ['REPROCESSED', 'Replaced by a re-process run'],
    ],
    t: ['Event', 'Event', 'Status history event', 'Bolt migration status history event'],
  },
  ACTOR: {
    type: 'C20',
    values: [['CLIENT', 'Client (this app)'], ['ENGINEER', 'Migration engineer'], ['SYSTEM', 'Background job']],
    t: ['By', 'Done by', 'Who caused the event', 'Bolt who caused the status history event'],
  },
  FILE_PATH: { type: 'C255', lower: true, t: ['Path', 'Path', 'Path in the repository', 'Bolt file path in the repository'] },
  FILE_NAME: { type: 'C120', lower: true, t: ['File', 'File name', 'File name', 'Bolt file name'] },
  FILE_KIND: {
    type: 'C10',
    values: [
      ['SNAPSHOT', 'Legacy grab snapshot'], ['XML', 'Smart Form XML export'], ['STYLE', 'Smart Style export'],
      ['DRIVER', 'Driver program source'], ['STATUS', 'Status file'], ['LEGACY', 'Legacy document added by the client'],
      ['ATTACH', 'Attachment to a message'],
    ],
    t: ['Kind', 'File kind', 'File kind', 'Bolt kind of file on the migration branch'],
  },
  SIZE_BYTES: { type: 'INT4', t: ['Size', 'Size (bytes)', 'Size in bytes', 'Bolt file size in bytes'] },
  REMOVED: { type: 'BOOL', t: ['Removed', 'Removed', 'Removed from the list', 'Bolt file removed from the list (kept on the branch)'] },
  LIB_CATEGORY: {
    type: 'C20',
    values: [['logo', 'Logos'], ['smartstyle', 'Smart Styles'], ['naming_standard', 'Naming standards'], ['policy', 'Policies']],
    lower: true,
    t: ['Category', 'Category', 'Global library category', 'Bolt global reference library category'],
  },
  PROVENANCE: { type: 'C255', lower: true, t: ['Note', 'Provenance note', 'Where the file came from', 'Bolt provenance note of a library file'] },
  PUSHED: { type: 'BOOL', t: ['Pushed', 'Pushed', 'Pushed to the repository', 'Bolt file pushed to the repository'] },
  SECRET_ID: {
    type: 'C20',
    values: [['GITHUB_TOKEN', 'GitHub token'], ['AI_KEY', 'AI API key']],
    t: ['Secret', 'Secret', 'Secret ID', 'Bolt secret ID'],
  },
  SECRET_VALUE: { type: 'STRG', lower: true, t: ['Value', 'Secret value', 'Secret value (encoded, never shown)', 'Bolt secret value (encoded, never exposed)'] },
};

// Standard SAP data elements (not generated).
const STD = {
  UUID: 'SYSUUID_X16', TS: 'TIMESTAMPL', USER: 'SYUNAME', BOOLX: 'ABAP_BOOLEAN', FORM: 'TDSFNAME',
  PACKAGE: 'DEVCLASS', PROG: 'PROGNAME', SYSID: 'SYSYSID', CLIENT: 'SYMANDT', DEST: 'RFCDEST',
};

const admin = [
  ['CREATED_BY', STD.USER], ['CREATED_AT', STD.TS], ['CHANGED_BY', STD.USER], ['CHANGED_AT', STD.TS],
  ['LOCAL_CHANGED', STD.TS],
];

// [field, catalog key | standard DE, key?]
const tables = [
  {
    name: 'ZABT_BOLT_SETUP', art: 'APPL2', text: 'Bolt: client setup (GitHub, AI, conventions)',
    fields: [
      ['SETUP_ID', 'SETUP_ID', true], ['CUSTOMER_NAME'], ['ADMIN_USERS'],
      ['GH_API_URL'], ['GH_DEST', STD.DEST], ['SSL_ID'], ['GH_TOKEN_SET'], ['GH_LOGIN'], ['GH_USER_NAME'],
      ['GH_SCOPES'], ['GH_CONNECTED_AT'], ['GH_REPO'], ['GH_BASE_BRANCH'], ['GH_BRANCH_PFX'], ['GH_PRIVATE'],
      ['GH_CAN_PUSH'], ['GH_CHECK_RES'], ['GH_CHECK_MSG'], ['GH_CHECKED_AT'], ['STATUS_FOLDER'], ['LIB_FOLDER'],
      ['AI_PROVIDER'], ['AI_MODEL'], ['AI_BASE_URL'], ['AI_DEST', STD.DEST], ['AI_MAX_TOKENS'], ['AI_KEY_SET'],
      ['AI_CHECK_RES'], ['AI_CHECK_MSG'], ['AI_CHECKED_AT'], ['FORM_PREFIXES'], ['COUNT_VOLUME'], ...admin,
    ],
  },
  {
    name: 'ZABT_BOLT_MIG', art: 'APPL1', text: 'Bolt: Smart Form migrations (basic status only)',
    fields: [
      ['MIG_UUID', STD.UUID, true], ['SERIAL_NO'], ['FORM_NAME', STD.FORM], ['FORM_DESCR'], ['DEV_PACKAGE', STD.PACKAGE],
      ['DRIVER_PROGS'], ['OUTPUT_TYPES'], ['RUN_NO'], ['REPROCESS_OF', STD.UUID], ['SUPERSEDED'], ['BRANCH_NAME'],
      ['FORM_SLUG'], ['PUSH_STATUS'], ['PUSH_MSG'], ['PUSH_ATTEMPTS'], ['PUSHED_AT', STD.TS], ['FILES_COUNT'],
      ['COMMIT_SHA'], ['MIG_STATUS'], ['WAITING_ON'], ['STOPPED'], ['CLAIMED_BY'], ['STATUS_UPDATED'], ['STATUS_SHA'],
      ['LAST_SYNC_AT', STD.TS], ['PICKED_UP_AT', STD.TS], ['STOPPED_AT', STD.TS], ['COMPLETED_AT', STD.TS],
      ['COMPLEXITY'], ['COMPLEXITY_INFO'], ['SOURCE_SYSID', STD.SYSID], ['SOURCE_CLIENT', STD.CLIENT], ...admin,
    ],
  },
  {
    name: 'ZABT_BOLT_HIST', art: 'APPL1', text: 'Bolt: migration status history (no texts)',
    fields: [
      ['MIG_UUID', STD.UUID, true], ['HIST_UUID', STD.UUID, true], ['EVENT_AT', STD.TS], ['HIST_EVENT'], ['ACTOR'],
      ['EVENT_USER', STD.USER], ['MIG_STATUS'], ['WAITING_ON'], ['STOPPED'], ['COMMIT_SHA'],
    ],
  },
  {
    name: 'ZABT_BOLT_FILE', art: 'APPL1', text: 'Bolt: files on each migration branch',
    fields: [
      ['MIG_UUID', STD.UUID, true], ['FILE_UUID', STD.UUID, true], ['FILE_KIND'], ['FILE_NAME'], ['FILE_PATH'],
      ['SIZE_BYTES'], ['COMMIT_SHA'], ['PUSHED_AT', STD.TS], ['PUSHED_BY', STD.USER], ['REMOVED'],
      ['REMOVED_AT', STD.TS], ['REMOVED_BY', STD.USER],
    ],
  },
  {
    name: 'ZABT_BOLT_LIB', art: 'APPL2', text: 'Bolt: global reference library files',
    fields: [
      ['LIB_UUID', STD.UUID, true], ['LIB_CATEGORY'], ['FILE_NAME'], ['FILE_PATH'], ['SIZE_BYTES'], ['PROVENANCE'],
      ['PUSHED'], ['PUSH_MSG'], ['COMMIT_SHA'], ...admin,
    ],
  },
  {
    name: 'ZABT_BOLT_SECRT', art: 'APPL2', text: 'Bolt: secrets (never exposed by the service)',
    fields: [['SECRET_ID', 'SECRET_ID', true], ['SECRET_VALUE'], ['CHANGED_BY', STD.USER], ['CHANGED_AT', STD.TS]],
  },
  {
    name: 'ZABT_BOLT_DRVIX', art: 'APPL1', text: 'Bolt: Smart Form driver program index',
    fields: [['FORM_NAME', STD.FORM, true], ['PROG_NAME', STD.PROG, true], ['INDEXED_AT', STD.TS]],
  },
];

// ---------------------------------------------------------------------------------------------
const wrap = (serializer, body) => `${BOM}<?xml version="1.0" encoding="utf-8"?>
<abapGit version="v1.0.0" serializer="${serializer}" serializer_version="v1.0.0">
 <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
  <asx:values>
${body}
  </asx:values>
 </asx:abap>
</abapGit>
`;

function dict(key) {
  const f = F[key];
  if (f.type === 'BOOL') return null; // standard ABAP_BOOLEAN, no own domain
  if (f.type === 'TS') return null; // standard TIMESTAMPL
  let datatype; let leng; let outlen;
  if (f.type === 'INT4') { datatype = 'INT4'; leng = 10; outlen = 10; }
  else if (f.type === 'STRG') { datatype = 'STRG'; leng = 0; outlen = 0; }
  else { datatype = 'CHAR'; leng = Number(f.type.slice(1)); outlen = leng; }
  return { datatype, leng, outlen };
}

// Fields whose catalog type is BOOL/TS use the standard data element.
const deOf = (key) => (F[key].type === 'BOOL' ? STD.BOOLX : F[key].type === 'TS' ? STD.TS : `ZAB_DE_BOLT_${key}`);

fs.mkdirSync(out, { recursive: true });
for (const f of fs.readdirSync(out)) if (/\.(doma|dtel|tabl)\.xml$/.test(f)) fs.unlinkSync(path.join(out, f));

let nDoma = 0; let nDtel = 0;
const used = new Set();
for (const t of tables) for (const [fname, ref] of t.fields) if (!ref || F[ref]) used.add(ref || fname);
for (const key of [...used].sort()) {
  const f = F[key];
  if (!f) { problems.push(`catalog entry ${key} missing`); continue; }
  const d = dict(key);
  const [s, m, l, descr] = f.t;
  check(s.length <= 10, `${key}: short label > 10`);
  check(m.length <= 20, `${key}: medium label > 20`);
  check(l.length <= 40, `${key}: long label > 40`);
  check(descr.length <= 60, `${key}: description > 60`);
  check(key.length <= 16, `${key}: field name > 16`);
  if (!d) continue;
  const doma = `ZAB_DM_BOLT_${key}`;
  const dtel = `ZAB_DE_BOLT_${key}`;
  check(doma.length <= 30 && dtel.length <= 30, `${key}: domain/data element name > 30`);
  const vals = f.values || [];
  for (const [v, txt] of vals) {
    check(v.length <= d.leng, `${key}: fixed value ${v} longer than the domain`);
    check(txt.length <= 60, `${key}: fixed value text > 60`);
    check(f.lower || v === v.toUpperCase(), `${key}: lower-case value ${v} needs lower: true`);
  }
  const ddl = [
    `    <DOMNAME>${doma}</DOMNAME>`, '    <DDLANGUAGE>E</DDLANGUAGE>', `    <DATATYPE>${d.datatype}</DATATYPE>`,
    `    <LENG>${pad(d.leng)}</LENG>`, `    <OUTPUTLEN>${pad(d.outlen)}</OUTPUTLEN>`,
  ];
  if (f.lower && d.datatype === 'CHAR') ddl.push('    <LOWERCASE>X</LOWERCASE>');
  if (vals.length) ddl.push('    <VALEXI>X</VALEXI>');
  ddl.push(`    <DDTEXT>${esc(descr)}</DDTEXT>`);
  let body = `   <DD01V>\n${ddl.join('\n')}\n   </DD01V>`;
  if (vals.length) {
    body += `\n   <DD07V_TAB>\n${vals.map(([v, txt], i) => `    <DD07V>
     <VALPOS>${pad(i + 1, 4)}</VALPOS>
     <DDLANGUAGE>E</DDLANGUAGE>
     <DOMVALUE_L>${esc(v)}</DOMVALUE_L>
     <DDTEXT>${esc(txt)}</DDTEXT>
    </DD07V>`).join('\n')}\n   </DD07V_TAB>`;
  }
  fs.writeFileSync(path.join(out, `${doma.toLowerCase()}.doma.xml`), wrap('LCL_OBJECT_DOMA', body), 'utf8');
  nDoma += 1;
  fs.writeFileSync(path.join(out, `${dtel.toLowerCase()}.dtel.xml`), wrap('LCL_OBJECT_DTEL', `   <DD04V>
    <ROLLNAME>${dtel}</ROLLNAME>
    <DDLANGUAGE>E</DDLANGUAGE>
    <DOMNAME>${doma}</DOMNAME>
    <HEADLEN>55</HEADLEN>
    <SCRLEN1>10</SCRLEN1>
    <SCRLEN2>20</SCRLEN2>
    <SCRLEN3>40</SCRLEN3>
    <DDTEXT>${esc(descr)}</DDTEXT>
    <REPTEXT>${esc(m)}</REPTEXT>
    <SCRTEXT_S>${esc(s)}</SCRTEXT_S>
    <SCRTEXT_M>${esc(m)}</SCRTEXT_M>
    <SCRTEXT_L>${esc(l)}</SCRTEXT_L>
    <DTELMASTER>E</DTELMASTER>
    <REFKIND>D</REFKIND>
   </DD04V>`), 'utf8');
  nDtel += 1;
}

const catalogDoc = [];
for (const t of tables) {
  check(t.name.length <= 16, `${t.name}: table name > 16`);
  check(/^ZABT_/.test(t.name), `${t.name}: table must start with ZABT_`);
  check(t.text.length <= 60, `${t.name}: description > 60`);
  const rows = t.fields.map(([fname, ref, key]) => {
    check(fname.length <= 16, `${t.name}.${fname}: field name > 16`);
    const rollname = ref && !F[ref] ? ref : deOf(ref || fname);
    if (ref && F[ref] && ref !== fname) problems.push(`${t.name}.${fname}: field must carry the name of its data element (${ref})`);
    catalogDoc.push(`| ${t.name} | ${fname}${key ? ' (key)' : ''} | ${rollname} |`);
    const L = ['    <DD03P>', `     <FIELDNAME>${fname}</FIELDNAME>`];
    if (key) L.push('     <KEYFLAG>X</KEYFLAG>');
    L.push(`     <ROLLNAME>${rollname}</ROLLNAME>`, '     <ADMINFIELD>0</ADMINFIELD>');
    if (key) L.push('     <NOTNULL>X</NOTNULL>');
    L.push('     <COMPTYPE>E</COMPTYPE>', '    </DD03P>');
    return L.join('\n');
  });
  const keys = t.fields.filter((x) => x[2]).map((x) => x[0]);
  check(t.fields[0][2], `${t.name}: key fields must come first`);
  check(t.fields.slice(0, keys.length).every((x) => x[2]), `${t.name}: key fields must be contiguous at the start`);
  fs.writeFileSync(path.join(out, `${t.name.toLowerCase()}.tabl.xml`), wrap('LCL_OBJECT_TABL', `   <DD02V>
    <TABNAME>${t.name}</TABNAME>
    <DDLANGUAGE>E</DDLANGUAGE>
    <TABCLASS>TRANSP</TABCLASS>
    <DDTEXT>${esc(t.text)}</DDTEXT>
    <CONTFLAG>A</CONTFLAG>
    <EXCLASS>1</EXCLASS>
   </DD02V>
   <DD09L>
    <TABNAME>${t.name}</TABNAME>
    <AS4LOCAL>A</AS4LOCAL>
    <TABKAT>0</TABKAT>
    <TABART>${t.art}</TABART>
    <BUFALLOW>N</BUFALLOW>
   </DD09L>
   <DD03P_TABLE>
${rows.join('\n')}
   </DD03P_TABLE>`), 'utf8');
}

// Field catalog for the docs (docs/07_object_catalog.md embeds it).
fs.writeFileSync(path.join(root, 'docs', 'generated_field_catalog.md'),
  `# Generated field catalog (do not edit - node tools/gen_ddic.mjs)\n\n| Table | Field | Data element |\n|---|---|---|\n${catalogDoc.join('\n')}\n`, 'utf8');

console.log(`${nDoma} domains, ${nDtel} data elements, ${tables.length} tables written to src/`);
if (problems.length) { console.error(`PROBLEMS:\n${problems.join('\n')}`); process.exit(1); }
console.log('DDIC OK');
