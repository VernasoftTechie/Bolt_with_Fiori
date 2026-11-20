// Bolt with Fiori - local mock of the ZAB_UI_BOLT OData V4 service, for UI work
// and demos without an SAP backend. No dependencies:
//   node tools/mock/mock-server.mjs        ->  http://localhost:8099/index.html
// Serves app/bolt-fiori/webapp with SAPUI5 from the SAP CDN, answers
// $metadata, $batch (reads and change sets), the CSRF handshake, and every
// action of the real service with the same checks and messages as the ABAP
// behaviour. All data is EXAMPLE data (marked as such) - it is not read from
// any SAP system or repository. Keep it in step with src/ (CLAUDE.md rule 6).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const PORT = Number(process.env.PORT || 8099);
const here = path.dirname(fileURLToPath(import.meta.url));
const webapp = path.resolve(here, '../../app/bolt-fiori/webapp');
const SERVICE = '/sap/opu/odata4/sap/zab_ui_bolt_o4/srvd/sap/zab_ui_bolt/0001/';
const NS = 'com.sap.gateway.srvd.zab_ui_bolt.v0001';
const UI5 = process.env.UI5_URL || 'https://sapui5.hana.ondemand.com/resources/sap-ui-core.js';
const MIME = { '.html': 'text/html', '.js': 'application/javascript', '.json': 'application/json', '.xml': 'application/xml',
  '.css': 'text/css', '.properties': 'text/plain; charset=utf-8', '.png': 'image/png', '.svg': 'image/svg+xml' };
const SYSID = 'S4D';
const ME = 'OPERATOR1';

// ----------------------------------------------------------------- model
const S = 'String'; const I = 'Int32'; const B = 'Boolean'; const G = 'Guid'; const TS = 'DateTimeOffset'; const DT = 'Date';
const admin = { CreatedBy: S, CreatedAt: TS, ChangedBy: S, ChangedAt: TS, LocalChanged: TS };
const T = {
  Migration: {
    keys: ['MigUuid'], etag: true,
    props: {
      MigUuid: G, SerialNo: I, FormName: S, FormDescr: S, DevPackage: S, DriverProgs: S, OutputTypes: S, RunNo: I,
      ReprocessOf: G, Superseded: B, BranchName: S, FormSlug: S, PushStatus: S, PushMsg: S, PushAttempts: I, PushedAt: TS,
      FilesCount: I, CommitSha: S, MigStatus: S, WaitingOn: S, Stopped: B, ClaimedBy: S, StatusUpdated: S, StatusSha: S,
      LastSyncAt: TS, PickedUpAt: TS, StoppedAt: TS, CompletedAt: TS, Complexity: S, ComplexityInfo: S, SourceSysid: S,
      SourceClient: S, ...admin,
    },
    nav: { _History: 'History', _File: 'MigrationFile' },
  },
  History: {
    keys: ['MigUuid', 'HistUuid'], parent: true,
    props: { MigUuid: G, HistUuid: G, EventAt: TS, HistEvent: S, Actor: S, EventUser: S, MigStatus: S, WaitingOn: S, Stopped: B, CommitSha: S },
  },
  MigrationFile: {
    keys: ['MigUuid', 'FileUuid'], parent: true,
    props: { MigUuid: G, FileUuid: G, FileKind: S, FileName: S, FilePath: S, SizeBytes: I, CommitSha: S, PushedAt: TS, PushedBy: S,
      Removed: B, RemovedAt: TS, RemovedBy: S },
  },
  Setup: {
    keys: ['SetupId'], etag: true,
    props: {
      SetupId: S, CustomerName: S, AdminUsers: S, GhApiUrl: S, GhDest: S, SslId: S, GhTokenSet: B, GhLogin: S, GhUserName: S,
      GhScopes: S, GhConnectedAt: TS, GhRepo: S, GhBaseBranch: S, GhBranchPfx: S, GhPrivate: B, GhCanPush: B, GhCheckRes: S,
      GhCheckMsg: S, GhCheckedAt: TS, StatusFolder: S, LibFolder: S, AiProvider: S, AiModel: S, AiBaseUrl: S, AiDest: S,
      AiMaxTokens: I, AiKeySet: B, AiCheckRes: S, AiCheckMsg: S, AiCheckedAt: TS, FormPrefixes: S, CountVolume: B, ...admin,
    },
  },
  Library: {
    keys: ['LibUuid'], etag: true,
    props: { LibUuid: G, LibCategory: S, FileName: S, FilePath: S, SizeBytes: I, Provenance: S, Pushed: B, PushMsg: S, CommitSha: S, ...admin },
  },
  SmartForm: {
    keys: ['FormName'],
    props: { FormName: S, Description: S, DevPackage: S, CreatedBy: S, CreatedOn: DT, ChangedBy: S, ChangedOn: DT, DriverProgs: S,
      OutputTypes: S, MigState: S, Selectable: B, LastSerialNo: I, LastRunNo: I, LastStatus: S, LastMigUuid: G },
  },
  StatusFile: {
    keys: ['MigUuid'],
    props: { MigUuid: G, StatusFound: B, MigStatus: S, StatusLabel: S, UpdatedAt: S, WaitingOn: S, Note: S, StopRequested: B, ClaimedBy: S,
      EntryCount: I, BranchUrl: S, Message: S },
  },
  Timeline: {
    keys: ['MigUuid', 'EntryNo'],
    props: { MigUuid: G, EntryNo: I, EntryAt: S, Heading: S, EntryText: S },
  },
  SystemInfo: {
    keys: ['SystemId'],
    props: { SystemId: S, Client: S, HostName: S, UserName: S, CustomerName: S, SetupExists: B, IsAdmin: B, AdminsDefined: B,
      GitHubReady: B, RepoReady: B, AiReady: B, Live: B, RepoUrl: S, IndexBuilt: B, AppVersion: S },
  },
};
const AI_P = { Provider: S, Model: S, BaseUrl: S, MaxTokens: I, ApiKey: S };
const REPO_P = { Repo: S, BranchPrefix: S };
const ACTIONS = {
  Migration: {
    commitSelection: { static: true, params: { FormNames: S }, returns: 'collection' },
    refreshAll: { static: true, params: {}, returns: 'collection' },
    pushToGitHub: { params: {}, returns: 'self' },
    refreshStatus: { params: {}, returns: 'self' },
    respond: { params: { Kind: S, Text: S, FilesJson: S }, returns: 'self' },
    requestStop: { params: { Reason: S }, returns: 'self' },
    resume: { params: {}, returns: 'self' },
    saveLegacyDocs: { params: { FilesJson: S, RemoveIds: S }, returns: 'self' },
    aiSummary: { params: {}, returns: 'text' },
  },
  Setup: {
    initialize: { static: true, params: {}, returns: 'self' },
    connectGitHub: { params: { Token: S }, returns: 'self' },
    disconnectGitHub: { params: {}, returns: 'self' },
    checkRepo: { params: REPO_P, returns: 'self' },
    createRepo: { params: REPO_P, returns: 'self' },
    saveRepo: { params: REPO_P, returns: 'self' },
    saveAi: { params: AI_P, returns: 'self' },
    testAi: { params: AI_P, returns: 'self' },
  },
  Library: { upload: { static: true, params: { Category: S, Provenance: S, FilesJson: S }, returns: 'collection' } },
};

function metadata() {
  const types = Object.entries(T).map(([set, t]) => {
    const props = Object.entries(t.props).map(([n, ty]) =>
      `<Property Name="${n}" Type="Edm.${ty}"${t.keys.includes(n) ? ' Nullable="false"' : ''}${ty === TS ? ' Precision="7"' : ''}/>`).join('');
    const nav = Object.entries(t.nav || {}).map(([n, target]) =>
      `<NavigationProperty Name="${n}" Type="Collection(${NS}.${target}Type)" Partner="_Migration"/>`).join('');
    const back = t.parent ? `<NavigationProperty Name="_Migration" Type="${NS}.MigrationType" Nullable="false" Partner="${set === 'History' ? '_History' : '_File'}"/>` : '';
    return `<EntityType Name="${set}Type"><Key>${t.keys.map((k) => `<PropertyRef Name="${k}"/>`).join('')}</Key>${props}${nav}${back}</EntityType>`;
  }).join('');
  const text = `<ComplexType Name="ZAB_CDS_A_BOLT_TEXT_RType"><Property Name="Text" Type="Edm.String"/></ComplexType>`;
  const actions = Object.entries(ACTIONS).flatMap(([set, acts]) => Object.entries(acts).map(([name, a]) => {
    const bind = a.static ? `Collection(${NS}.${set}Type)` : `${NS}.${set}Type`;
    const params = Object.entries(a.params).map(([n, ty]) => `<Parameter Name="${n}" Type="Edm.${ty}"/>`).join('');
    let ret = `<ReturnType Type="${NS}.${set}Type" Nullable="false"/>`;
    if (a.returns === 'collection') ret = `<ReturnType Type="Collection(${NS}.${set}Type)" Nullable="false"/>`;
    if (a.returns === 'text') ret = `<ReturnType Type="${NS}.ZAB_CDS_A_BOLT_TEXT_RType" Nullable="false"/>`;
    return `<Action Name="${name}" IsBound="true"${a.static ? '' : ' EntitySetPath="_it"'}><Parameter Name="_it" Type="${bind}" Nullable="false"/>${params}${ret}</Action>`;
  })).join('');
  const sets = Object.keys(T).map((set) => {
    const nav = Object.entries(T[set].nav || {}).map(([n, target]) => `<NavigationPropertyBinding Path="${n}" Target="${target}"/>`).join('');
    const back = T[set].parent ? '<NavigationPropertyBinding Path="_Migration" Target="Migration"/>' : '';
    return `<EntitySet Name="${set}" EntityType="${NS}.${set}Type">${nav}${back}</EntitySet>`;
  }).join('');
  return `<?xml version="1.0" encoding="utf-8"?><edmx:Edmx Version="4.0" xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx"><edmx:DataServices><Schema Namespace="${NS}" xmlns="http://docs.oasis-open.org/odata/ns/edm">${types}${text}${actions}<EntityContainer Name="Container">${sets}</EntityContainer></Schema></edmx:DataServices></edmx:Edmx>`;
}

// ------------------------------------------------------------------ data
const iso = (d = new Date()) => d.toISOString();
const ago = (h) => new Date(Date.now() - h * 3600e3);
const uuid = () => crypto.randomUUID();
const sha = () => crypto.randomBytes(20).toString('hex');
const D = '—';
const LABELS = { queued: 'Queued', in_progress: 'In Progress', interface_completed: 'Interface Completed', waiting_manual: `Waiting ${D} Manual Activity`,
  layout_in_progress: 'Form Design In Progress', completed: 'Migration Completed', open_for_concerns: `Open ${D} Awaiting Review` };

const db = {
  Setup: [{
    SetupId: 'DEFAULT', CustomerName: 'Dangote (example data)', AdminUsers: '', GhApiUrl: 'https://api.github.com', GhDest: '', SslId: 'ANONYM',
    GhTokenSet: true, GhLogin: 'VernasoftTechie', GhUserName: 'Vernasoft Techie', GhScopes: '', GhConnectedAt: iso(ago(300)),
    GhRepo: 'VernasoftTechie/Smartform-Adobe-Migration', GhBaseBranch: 'main', GhBranchPfx: 'vernasofttechie', GhPrivate: true,
    GhCanPush: true, GhCheckRes: 'OK', GhCheckMsg: '✓ VernasoftTechie/Smartform-Adobe-Migration · private · default branch main · push access',
    GhCheckedAt: iso(ago(2)), StatusFolder: 'docs/legacy_grab', LibFolder: 'docs/global_data', AiProvider: 'anthropic', AiModel: 'claude-sonnet-5-5',
    AiBaseUrl: '', AiDest: '', AiMaxTokens: 4096, AiKeySet: true, AiCheckRes: 'OK', AiCheckMsg: 'Connection OK - Anthropic (claude-sonnet-5-5) responded.',
    AiCheckedAt: iso(ago(2)), FormPrefixes: 'Z,Y', CountVolume: true, CreatedBy: 'BOLTADMIN', CreatedAt: iso(ago(400)), ChangedBy: 'BOLTADMIN',
    ChangedAt: iso(ago(1)), LocalChanged: iso(ago(1)),
  }],
  Library: [],
  forms: [
    ['YMM_PO_SMARTFORM', 'Purchase order', 'ZMM', 'YMM_PO_PROGRAM', 'EF/NEU'],
    ['ZMMCG_PO_SF', 'Purchase order (CG)', 'ZMM', 'ZCGMMPOP001, ZCGMMPOP002', 'EF/ZCG1'],
    ['ZMMET_PO_SF', 'Purchase order (ET)', 'ZMM', 'ZMMET_PO_DRIVER_RP', 'EF/ZET1'],
    ['ZMM_PO_DEMO', 'Purchase order demo', 'ZMM', '', ''],
    ['ZFING_CUST_ACT_SUM', 'Customer account summary', 'ZFI', 'ZFI_CUST_ACT_STMT_F01', 'V3/ZCAS'],
    ['ZCGSD_INVOICE', 'Sales invoice', 'ZSD', 'ZCGSDINV002', 'V3/ZINV'],
    ['ZSD_DELIVERY_NOTE', 'Delivery note', 'ZSD', 'ZSD_DELNOTE_PRINT', 'V2/ZLD0'],
    ['ZSD_PROFORMA', 'Proforma invoice', 'ZSD', 'ZSD_PROFORMA_DRV', 'V1/ZPRO'],
    ['ZFI_PAYMENT_ADVICE', 'Payment advice', 'ZFI', 'ZFI_PAYADV', ''],
    ['ZHR_PAYSLIP', 'Pay slip', 'ZHR', 'ZHR_PAYSLIP_PRINT', ''],
    ['ZMM_GRN_NOTE', 'Goods receipt note', 'ZMM', 'ZMM_GRN_DRIVER', 'ME/ZGRN'],
    ['ZMM_RESERVATION', 'Issue reservation', 'ZMM', 'ZMM_RESV_PRINT', ''],
    ['YSD_ATC', 'Authority to collect', 'YSD', 'ZSD_DRIVER_ATC', 'V3/ZATC'],
    ['YFI_CHEQUE', 'Cheque print', 'YFI', 'YFI_CHEQUE_PRINT', ''],
  ],
  Migration: [], History: [], MigrationFile: [],
  sf: {}, // the branch status files, per MigUuid: { status, waitingOn, note, stop, claimedBy, updated, entries: [] }
};

const files = (form, branch) => [[`${form}.md`, 'SNAPSHOT', 18450], [`${form.toLowerCase()}.xml`, 'XML', 412300],
  [`style_z${form.toLowerCase().slice(1, 6)}.xml`, 'STYLE', 9800], [`driver_${form}_DRV.txt`, 'DRIVER', 22110],
  [`${form.toLowerCase()}_status.md`, 'STATUS', 900, 'docs/legacy_grab']].map(([n, k, s, dir]) => ({ name: n, kind: k, size: s, path: `${dir || branch}/${n}` }));

function hist(mig, event, actor = 'CLIENT', extra = {}) {
  db.History.push({ MigUuid: mig.MigUuid, HistUuid: uuid(), EventAt: iso(), HistEvent: event, Actor: actor,
    EventUser: actor === 'ENGINEER' ? '' : ME, MigStatus: mig.MigStatus, WaitingOn: mig.WaitingOn, Stopped: !!mig.Stopped, CommitSha: '', ...extra });
}
function addFiles(mig, list, commit) {
  list.forEach((f) => db.MigrationFile.push({ MigUuid: mig.MigUuid, FileUuid: uuid(), FileKind: f.kind, FileName: f.name, FilePath: f.path,
    SizeBytes: f.size, CommitSha: commit, PushedAt: iso(), PushedBy: ME, Removed: false, RemovedAt: null, RemovedBy: '' }));
}
function entry(mig, heading, text) {
  const s = db.sf[mig.MigUuid];
  s.entries.push({ at: iso(), heading, text });
  s.updated = iso();
}
function syncRow(mig) {
  const s = db.sf[mig.MigUuid];
  if (!s) return;
  const changed = mig.MigStatus !== s.status || mig.WaitingOn !== s.waitingOn || !!mig.Stopped !== s.stop;
  Object.assign(mig, { MigStatus: s.status, WaitingOn: s.waitingOn, Stopped: s.stop, ClaimedBy: s.claimedBy, StatusUpdated: s.updated,
    LastSyncAt: iso(), LocalChanged: iso() });
  if (!mig.PickedUpAt && (s.claimedBy || s.status !== 'queued')) mig.PickedUpAt = iso();
  if (s.status === 'completed' && !mig.CompletedAt) mig.CompletedAt = iso();
  return changed;
}

function seed(form, serial, hours, sf, opts = {}) {
  const meta = db.forms.find((f) => f[0] === form);
  const run = opts.run || 1;
  const branch = `vernasofttechie-${form.toLowerCase()}${run > 1 ? `-r${run}` : ''}`;
  const mig = {
    MigUuid: uuid(), SerialNo: serial, FormName: form, FormDescr: meta[1], DevPackage: meta[2], DriverProgs: meta[3], OutputTypes: meta[4],
    RunNo: run, ReprocessOf: opts.prev || null, Superseded: !!opts.superseded, BranchName: branch, FormSlug: form.toLowerCase(),
    PushStatus: opts.push || 'PUSHED', PushMsg: opts.pushMsg || `Created branch ${branch} with 5 file(s) in one commit. (example)`,
    PushAttempts: 1, PushedAt: opts.push === 'FAILED' ? null : iso(ago(hours)), FilesCount: opts.push === 'FAILED' ? 0 : 5, CommitSha: sha(),
    MigStatus: 'queued', WaitingOn: 'engineer', Stopped: false, ClaimedBy: '', StatusUpdated: '', StatusSha: sha(), LastSyncAt: iso(ago(0.2)),
    PickedUpAt: null, StoppedAt: null, CompletedAt: null, Complexity: ['low', 'medium', 'high'][serial % 3],
    ComplexityInfo: '3 window(s), 1 table/loop section(s), 2 condition(s), 1 language(s), 1 embedded code node(s), 12 interface parameter(s).',
    SourceSysid: SYSID, SourceClient: '100', CreatedBy: ME, CreatedAt: iso(ago(hours)), ChangedBy: ME, ChangedAt: iso(ago(1)), LocalChanged: iso(ago(1)),
  };
  db.Migration.push(mig);
  db.History.push({ MigUuid: mig.MigUuid, HistUuid: uuid(), EventAt: iso(ago(hours)), HistEvent: 'COMMITTED', Actor: 'CLIENT', EventUser: ME,
    MigStatus: 'queued', WaitingOn: 'engineer', Stopped: false, CommitSha: '' });
  if (mig.PushStatus === 'FAILED') {
    db.History.push({ MigUuid: mig.MigUuid, HistUuid: uuid(), EventAt: iso(ago(hours)), HistEvent: 'PUSH_FAILED', Actor: 'SYSTEM', EventUser: ME,
      MigStatus: 'queued', WaitingOn: 'engineer', Stopped: false, CommitSha: '' });
    return mig;
  }
  addFiles(mig, files(form, branch), mig.CommitSha);
  db.History.push({ MigUuid: mig.MigUuid, HistUuid: uuid(), EventAt: iso(ago(hours)), HistEvent: 'PUSHED', Actor: 'CLIENT', EventUser: ME,
    MigStatus: 'queued', WaitingOn: 'engineer', Stopped: false, CommitSha: mig.CommitSha });
  db.sf[mig.MigUuid] = { status: 'queued', waitingOn: 'engineer', note: 'Waiting for the migration engineer to pick this up.', stop: false,
    claimedBy: '', updated: iso(ago(hours)), entries: [{ at: iso(ago(hours)), heading: 'Queued',
      text: `Migration submitted with 5 reference file(s).\n\nSent by Bolt with Fiori from SAP system ${SYSID} client 100 by user ${ME} (serial no. ${serial}). (example)` }] };
  Object.assign(db.sf[mig.MigUuid], sf || {});
  (sf && sf.more || []).forEach(([h, heading, text]) => db.sf[mig.MigUuid].entries.push({ at: iso(ago(h)), heading, text }));
  syncRow(mig);
  if (mig.MigStatus !== 'queued') {
    db.History.push({ MigUuid: mig.MigUuid, HistUuid: uuid(), EventAt: iso(ago(hours - 1)), HistEvent: 'STATUS', Actor: 'ENGINEER', EventUser: '',
      MigStatus: mig.MigStatus, WaitingOn: mig.WaitingOn, Stopped: mig.Stopped, CommitSha: '' });
  }
  return mig;
}

seed('ZCGSD_INVOICE', 1, 1150, { status: 'completed', waitingOn: '', note: '', claimedBy: 'Window-1', more: [
  [1149, 'Picked up', 'Window-1 picked this migration up.'],
  [1100, 'Migration completed', 'Closed on your confirmation that the layout activated and everything looks right.']] });
seed('ZFING_CUST_ACT_SUM', 2, 1000, { status: 'waiting_manual', waitingOn: 'client', claimedBy: 'Window-2',
  note: 'Pull the branch in abapGit onto the form, activate it in SFP and check the **Context** tree shows all 24 nodes.', more: [
  [999, 'Interface prepared', 'The form interface has been prepared from the legacy export:\n- 19 custom import parameters and 5 tables\n- 13 global data fields\n- `LV_WAERK` added as the currency key'],
  [998, 'Context tree built', 'Please:\n1. Pull this branch onto the form in SFP.\n2. Check the Context tree shows all **24 nodes**.\n3. Confirm, or report the exact error.']] });
seed('ZMMET_PO_SF', 3, 60, { status: 'layout_in_progress', waitingOn: 'engineer', claimedBy: 'Window-4', note: 'Layout in progress.', more: [
  [59, 'Picked up', 'Window-4 picked this migration up.'], [20, 'Layout started', 'The Context imported cleanly; layout in progress.']] });
const stoppedDemo = seed('ZSD_PROFORMA', 4, 30, { status: 'in_progress', waitingOn: 'engineer', claimedBy: 'Window-3', stop: true, note: '', more: [
  [29, 'Picked up', 'Window-3 picked this migration up.'], [5, 'Stop requested', 'Client requested a stop: the driver program is being changed - we will re-process later.']] });
stoppedDemo.StoppedAt = iso(ago(5));
seed('ZHR_PAYSLIP', 5, 3, null, { push: 'FAILED', pushMsg: 'Smart Form ZHR_PAYSLIP could not be loaded for export: the form is locked by user HRDEV. (example)' });

// ------------------------------------------------------------- derived sets
function smartForms() {
  return db.forms.map(([FormName, Description, DevPackage, DriverProgs, OutputTypes], i) => {
    const runs = db.Migration.filter((m) => m.FormName === FormName).sort((a, b) => b.RunNo - a.RunNo);
    const last = runs[0];
    let MigState = 'NONE'; let Selectable = true;
    if (last) {
      if (last.MigStatus === 'completed') { MigState = 'COMPLETED'; Selectable = false; }
      else if (last.Stopped) { MigState = 'STOPPED'; Selectable = true; }
      else { MigState = 'ACTIVE'; Selectable = false; }
    }
    return { FormName, Description, DevPackage, CreatedBy: 'ABAP07', CreatedOn: '2015-03-25', ChangedBy: 'C.KKUMAR',
      ChangedOn: `2026-${String((i % 9) + 1).padStart(2, '0')}-15`, DriverProgs, OutputTypes, MigState, Selectable,
      LastSerialNo: last ? last.SerialNo : 0, LastRunNo: last ? last.RunNo : 0, LastStatus: last ? (last.PushStatus !== 'PUSHED' ? 'draft' : last.MigStatus) : '', LastMigUuid: last ? last.MigUuid : null };
  });
}
function statusRow(m) {
  const s = db.sf[m.MigUuid];
  if (!s) return { MigUuid: m.MigUuid, StatusFound: false, Message: m.PushStatus === 'PUSHED' ? 'The status file is not on the branch (yet).' : 'Not on GitHub yet - the timeline starts once the migration is sent.' };
  return { MigUuid: m.MigUuid, StatusFound: true, MigStatus: s.status, StatusLabel: LABELS[s.status] || s.status, UpdatedAt: s.updated, WaitingOn: s.waitingOn,
    Note: s.note, StopRequested: s.stop, ClaimedBy: s.claimedBy, EntryCount: s.entries.length,
    BranchUrl: `https://github.com/${db.Setup[0].GhRepo}/tree/${m.BranchName}`, Message: '' };
}
function sysInfo() {
  const s = db.Setup[0];
  const github = !!s.GhTokenSet; const repo = github && !!s.GhRepo && !!s.GhCanPush;
  const ai = s.AiProvider === 'mock' || !!s.AiKeySet;
  const admins = (s.AdminUsers || '').toUpperCase().split(',').map((x) => x.trim()).filter(Boolean);
  return { SystemId: SYSID, Client: '100', HostName: 's4d-app01 (example)', UserName: ME, CustomerName: s.CustomerName, SetupExists: true,
    IsAdmin: !admins.length || admins.includes(ME), AdminsDefined: admins.length > 0, GitHubReady: github, RepoReady: repo, AiReady: ai,
    Live: github && repo && ai, RepoUrl: s.GhRepo ? `https://github.com/${s.GhRepo}` : '', IndexBuilt: true, AppVersion: '2.1.1 (mock)' };
}

// --------------------------------------------------------------- helpers
class Http extends Error { constructor(status, message) { super(message); this.status = status; } }
const msg = (text, severity = 1) => ({ code: 'BOLT/000', message: text, numericSeverity: severity, target: '', transition: true });
const fail = (text) => { throw new Http(400, text); };

function parseKey(seg) {
  const m = /^(\w+)\((.*)\)$/.exec(seg);
  if (!m) return { set: seg };
  const keys = {};
  m[2].split(',').forEach((pair) => {
    const [k, v] = pair.includes('=') ? pair.split('=') : [T[m[1]].keys[0], pair];
    keys[k] = decodeURIComponent(v).replace(/^'(.*)'$/, '$1');
  });
  return { set: m[1], keys };
}
function rowsOf(set) {
  if (set === 'SmartForm') return smartForms();
  if (set === 'SystemInfo') return [sysInfo()];
  if (set === 'StatusFile') return db.Migration.map(statusRow);
  if (set === 'Timeline') {
    return db.Migration.flatMap((m) => (db.sf[m.MigUuid] ? db.sf[m.MigUuid].entries : [])
      .map((e, i) => ({ MigUuid: m.MigUuid, EntryNo: i + 1, EntryAt: e.at, Heading: e.heading, EntryText: e.text })));
  }
  return db[set] || [];
}
function find(set, keys) {
  const row = rowsOf(set).find((r) => Object.entries(keys).every(([k, v]) => String(r[k]) === String(v)));
  if (!row) throw new Http(404, `${set} not found`);
  return row;
}
function shape(set, row) {
  const out = {};
  if (T[set].etag && row.LocalChanged) out['@odata.etag'] = `W/"${row.LocalChanged}"`;
  Object.keys(T[set].props).forEach((p) => { out[p] = row[p] === undefined ? null : row[p]; });
  return out;
}
function applyFilter(rows, filter) {
  if (!filter) return rows;
  const conds = filter.split(/\s+and\s+/i).map((c) => /^\(?(\w+)\s+eq\s+'?([^')]*)'?\)?$/.exec(c.trim())).filter(Boolean);
  return rows.filter((r) => conds.every(([, f, v]) => String(r[f]) === v));
}
function touch(row) { row.LocalChanged = iso(); row.ChangedAt = iso(); row.ChangedBy = ME; }
function parseFiles(json) {
  if (!json) return [];
  try { return JSON.parse(json).filter((f) => f.content); } catch { fail('The attached files could not be read.'); }
  return [];
}
const sizeOf = (b64) => Math.round(String(b64 || '').length * 0.75);
function isAdmin() { return sysInfo().IsAdmin; }

// ------------------------------------------------------------- handlers
async function handle(method, url, body) {
  const [pathPart, query = ''] = url.split('?');
  const q = Object.fromEntries(query.split('&').filter(Boolean).map((kv) => { const [k, v = ''] = kv.split('='); return [decodeURIComponent(k), decodeURIComponent(v.replace(/\+/g, ' '))]; }));
  const segs = pathPart.split('/').filter(Boolean);
  const first = parseKey(segs[0] || '');
  const actionSeg = segs.find((s) => s.startsWith(`${NS}.`));
  const messages = [];

  if (actionSeg) {
    const name = actionSeg.slice(NS.length + 1).replace(/\(.*$/, '');
    const p = body ? JSON.parse(body || '{}') : {};
    return runAction(first.set, first.keys, name, p, messages);
  }
  if (method === 'GET') {
    if (first.keys && segs.length === 1) return { body: shape(first.set, find(first.set, first.keys)) };
    let set = first.set;
    let rows;
    if (first.keys && segs[1]) {
      set = T[first.set].nav[segs[1]];
      rows = db[set].filter((r) => r.MigUuid === first.keys.MigUuid);
    } else {
      rows = rowsOf(set);
    }
    rows = applyFilter(rows, q.$filter);
    if (set === 'SmartForm') await new Promise((r) => setTimeout(r, 300));
    if (q.$orderby) {
      const order = q.$orderby.split(',').map((o) => o.trim().split(' '));
      rows = [...rows].sort((a, b) => {
        for (const [f, dir] of order) {
          const c = a[f] > b[f] ? 1 : a[f] < b[f] ? -1 : 0;
          if (c) return dir === 'desc' ? -c : c;
        }
        return 0;
      });
    }
    const count = rows.length;
    const skip = Number(q.$skip || 0);
    const top = q.$top ? Number(q.$top) : rows.length;
    const value = rows.slice(skip, skip + top).map((r) => shape(set, r));
    return { body: { ...(q.$count === 'true' ? { '@odata.count': count } : {}), value } };
  }
  if (method === 'PATCH' && first.set === 'Setup') {
    if (!isAdmin()) throw new Http(403, 'Only Bolt administrators can change the configuration.');
    const row = find('Setup', first.keys);
    const data = JSON.parse(body || '{}');
    if (data.AdminUsers && !data.AdminUsers.split(',').map((x) => x.trim()).includes(ME)) {
      fail(`Add your own user ID (${ME}) to the administrators, or you lose access to this page.`);
    }
    Object.assign(row, data);
    touch(row);
    return { body: shape('Setup', row) };
  }
  if (method === 'DELETE' && first.set === 'Library') {
    if (!isAdmin()) throw new Http(403, 'Only Bolt administrators can change the library.');
    const row = find('Library', first.keys);
    db.Library.splice(db.Library.indexOf(row), 1);
    return { status: 204 };
  }
  throw new Http(405, `${method} ${url} not supported by the mock`);
}

async function runAction(set, keys, name, p, messages) {
  const self = keys ? find(set, keys) : null;
  const one = (row, s = set) => ({ body: shape(s, row), messages });
  const wait = (ms) => new Promise((r) => setTimeout(r, ms));

  if (set === 'Setup') {
    const s = db.Setup[0];
    if (name !== 'initialize' && !isAdmin()) throw new Http(403, 'Only Bolt administrators can change the configuration.');
    switch (name) {
      case 'initialize': return one(s);
      case 'connectGitHub': {
        await wait(500);
        if (!p.Token) fail('Paste a GitHub token to connect.');
        if (p.Token.length < 20) fail("That token wasn't accepted by GitHub. Copy a fresh token - it may be wrong, expired, or missing a character - and paste it again.");
        Object.assign(s, { GhTokenSet: true, GhLogin: 'VernasoftTechie', GhUserName: 'Vernasoft Techie', GhScopes: p.Token.startsWith('ghp_') ? 'repo' : '', GhConnectedAt: iso() });
        touch(s); messages.push(msg('Connected as VernasoftTechie (Vernasoft Techie).'));
        return one(s);
      }
      case 'disconnectGitHub':
        Object.assign(s, { GhTokenSet: false, GhLogin: '', GhUserName: '', GhScopes: '', GhCanPush: false, GhCheckRes: '', GhCheckMsg: '' });
        touch(s); messages.push(msg('GitHub disconnected - the token was removed from this system.'));
        return one(s);
      case 'checkRepo': {
        await wait(400);
        const repo = String(p.Repo || '').replace(/^https?:\/\/[^/]+\//, '').replace(/\.git$/, '');
        if (!/^[^/\s]+\/[^/\s]+$/.test(repo)) { messages.push(msg("That doesn't look like a repository address. Use owner/name (like octocat/Hello-World) or the full https://github.com/... URL.", 3)); return one(s); }
        if (/missing/i.test(repo)) { messages.push(msg(`Couldn't find "${repo}", or your token can't access it. Check the repository owner/name and that your token has access.`, 3)); return one(s); }
        messages.push(msg(`✓ ${repo} · private · default branch main · push access`));
        return one(s);
      }
      case 'createRepo': {
        await wait(600);
        const name2 = String(p.Repo || '').split('/').pop();
        if (!/^[A-Za-z0-9._-]{1,100}$/.test(name2)) fail('Use only letters, numbers, dots, dashes and underscores in the repository name (no spaces).');
        Object.assign(s, { GhRepo: `${s.GhLogin}/${name2}`, GhCanPush: true, GhPrivate: true, GhBaseBranch: 'main', GhCheckRes: 'OK',
          GhCheckMsg: `✓ ${s.GhLogin}/${name2} · private · default branch main · push access` });
        touch(s); messages.push(msg(`Created ${s.GhRepo} (private, default branch main) - it is now the target repository.`));
        return one(s);
      }
      case 'saveRepo': {
        await wait(400);
        const repo = String(p.Repo || '').replace(/^https?:\/\/[^/]+\//, '').replace(/\.git$/, '');
        if (!/^[^/\s]+\/[^/\s]+$/.test(repo)) fail("That doesn't look like a repository address. Use owner/name (like octocat/Hello-World) or the full https://github.com/... URL.");
        if (!/^[a-z0-9._-]*$/.test(p.BranchPrefix || '')) fail('Use only lower-case letters, numbers, dots, dashes and underscores in the branch prefix.');
        Object.assign(s, { GhRepo: repo, GhBranchPfx: p.BranchPrefix || '', GhCanPush: true, GhCheckRes: 'OK', GhCheckMsg: `✓ ${repo} · private · default branch main · push access` });
        touch(s); messages.push(msg('Repository settings saved.'));
        return one(s);
      }
      case 'saveAi': {
        const prov = p.Provider || 'mock';
        const keySaved = s.AiKeySet && s.AiProvider === prov;
        if (prov !== 'mock' && !p.ApiKey && !keySaved) fail('Enter an API key for this provider to save or test.');
        Object.assign(s, { AiProvider: prov, AiModel: p.Model || '', AiBaseUrl: p.BaseUrl || '', AiMaxTokens: p.MaxTokens || 4096,
          AiKeySet: prov === 'mock' ? false : (p.ApiKey ? true : s.AiKeySet) });
        touch(s); messages.push(msg(`AI provider saved - ${{ openai: 'OpenAI', anthropic: 'Anthropic' }[prov] || 'Built-in (offline)'}.`));
        return one(s);
      }
      case 'testAi': {
        await wait(700);
        const prov = p.Provider || 'mock';
        const label = { openai: 'OpenAI', anthropic: 'Anthropic' }[prov] || 'Built-in (offline)';
        const model = p.Model || { openai: 'gpt-4o-mini', anthropic: 'claude-sonnet-5-5' }[prov] || 'built-in';
        if (prov !== 'mock' && !p.ApiKey && !(s.AiKeySet && s.AiProvider === prov)) {
          Object.assign(s, { AiCheckRes: 'ERROR', AiCheckMsg: 'Enter an API key for this provider to save or test.' });
          messages.push(msg(s.AiCheckMsg, 3));
        } else {
          Object.assign(s, { AiCheckRes: 'OK', AiCheckMsg: `Connection OK - ${label} (${model}) responded.` });
          messages.push(msg(s.AiCheckMsg));
        }
        s.AiCheckedAt = iso();
        return one(s);
      }
      default: fail(`Unknown action ${name}`);
    }
  }

  if (set === 'Library') {
    if (!isAdmin()) throw new Http(403, 'Only Bolt administrators can change the library.');
    if (!p.Category) fail('Choose a category first.');
    const list = parseFiles(p.FilesJson);
    if (!list.length) fail('Choose at least one file.');
    await wait(600);
    const folder = { logo: 'logos', smartstyle: 'styles', naming_standard: 'naming_standards', policy: 'policies' }[p.Category];
    const commit = sha();
    const rows = list.map((f) => ({ LibUuid: uuid(), LibCategory: p.Category, FileName: f.name, FilePath: `docs/global_data/${folder}/${f.name}`,
      SizeBytes: sizeOf(f.content), Provenance: p.Provenance || '', Pushed: true, PushMsg: `Pushed to docs/global_data/${folder}/ on main.`,
      CommitSha: commit, CreatedBy: ME, CreatedAt: iso(), ChangedBy: ME, ChangedAt: iso(), LocalChanged: iso() }));
    db.Library.push(...rows);
    messages.push(msg(`${rows.length} file(s) added to ${folder} - Pushed to docs/global_data/${folder}/ on main.`));
    return { body: { value: rows.map((r) => shape('Library', r)) }, messages };
  }

  if (set !== 'Migration') fail(`Unknown action ${name}`);
  const sf = self ? db.sf[self.MigUuid] : null;
  const needPushed = () => {
    if (self.Superseded) fail(`${self.FormName} (serial no. ${self.SerialNo}) was replaced by a re-process run - work on the newer one.`);
    if (self.PushStatus !== 'PUSHED') fail(`${self.FormName} is not on GitHub yet - use "Send to GitHub" first.`);
  };

  switch (name) {
    case 'commitSelection': {
      const sys = sysInfo();
      let serial = Math.max(0, ...db.Migration.map((m) => m.SerialNo));
      const created = [];
      const seen = new Set();
      String(p.FormNames || '').split(/[,\n]/).map((x) => x.trim().toUpperCase()).filter(Boolean).forEach((form) => {
        if (seen.has(form)) return;
        seen.add(form);
        const meta = db.forms.find((f) => f[0] === form);
        if (!meta) { messages.push(msg(`${form} does not exist on system ${SYSID} - skipped.`, 3)); return; }
        const last = db.Migration.filter((m) => m.FormName === form).sort((a, b) => b.RunNo - a.RunNo)[0];
        if (last && last.MigStatus === 'completed') { messages.push(msg(`${form} is already migrated (serial no. ${last.SerialNo}) - skipped.`, 3)); return; }
        if (last && !last.Stopped) { messages.push(msg(`${form} is already in migration (serial no. ${last.SerialNo}) - skipped.`, 3)); return; }
        const run = last ? last.RunNo + 1 : 1;
        serial += 1;
        const branch = `vernasofttechie-${form.toLowerCase()}${run > 1 ? `-r${run}` : ''}`;
        const mig = { MigUuid: uuid(), SerialNo: serial, FormName: form, FormDescr: meta[1], DevPackage: meta[2], DriverProgs: meta[3], OutputTypes: meta[4],
          RunNo: run, ReprocessOf: last ? last.MigUuid : null, Superseded: false, BranchName: branch, FormSlug: form.toLowerCase(), PushStatus: 'PENDING',
          PushMsg: '', PushAttempts: 0, PushedAt: null, FilesCount: 0, CommitSha: '', MigStatus: 'queued', WaitingOn: 'engineer', Stopped: false,
          ClaimedBy: '', StatusUpdated: '', StatusSha: '', LastSyncAt: null, PickedUpAt: null, StoppedAt: null, CompletedAt: null, Complexity: '',
          ComplexityInfo: '', SourceSysid: SYSID, SourceClient: '100', CreatedBy: ME, CreatedAt: iso(), ChangedBy: ME, ChangedAt: iso(), LocalChanged: iso() };
        db.Migration.push(mig);
        hist(mig, 'COMMITTED');
        if (last) { last.Superseded = true; touch(last); hist(last, 'REPROCESSED'); }
        created.push(mig);
      });
      if (created.length) messages.push(sys.RepoReady ? msg(`${created.length} Smart Form(s) committed for migration.`) : msg(`${created.length} Smart Form(s) saved as drafts - GitHub is not connected yet. Send them from the Drafts tab once Setup is complete.`, 3));
      return { body: { value: created.map((r) => shape('Migration', r)) }, messages };
    }
    case 'pushToGitHub': {
      if (self.Superseded) fail(`${self.FormName} (serial no. ${self.SerialNo}) was replaced by a re-process run - work on the newer one.`);
      if (self.Stopped) fail(`${self.FormName} is stopped - resume it first, or select it again for a re-process run.`);
      if (self.PushStatus === 'PUSHED') { messages.push(msg(`${self.FormName} is already on GitHub.`, 2)); return one(self); }
      await wait(1200);
      self.PushAttempts += 1;
      if (self.FormName === 'ZHR_PAYSLIP') {
        Object.assign(self, { PushStatus: 'FAILED', PushMsg: 'Smart Form ZHR_PAYSLIP could not be loaded for export: the form is locked by user HRDEV. (example)' });
        touch(self); hist(self, 'PUSH_FAILED', 'CLIENT'); // sent by hand (the sync job would write SYSTEM)
        messages.push(msg(`${self.FormName}: ${self.PushMsg}`, 3));
        return one(self);
      }
      const list = files(self.FormName, self.BranchName);
      const commit = sha();
      addFiles(self, list, commit);
      Object.assign(self, { PushStatus: 'PUSHED', PushedAt: iso(), FilesCount: list.length, CommitSha: commit, Complexity: ['low', 'medium', 'high'][self.SerialNo % 3],
        ComplexityInfo: '4 window(s), 2 table/loop section(s), 5 condition(s), 1 language(s), 2 embedded code node(s), 14 interface parameter(s).',
        PushMsg: `Created branch ${self.BranchName} with ${list.length} file(s) in one commit.` });
      const prev = self.ReprocessOf ? db.Migration.find((m) => m.MigUuid === self.ReprocessOf) : null;
      db.sf[self.MigUuid] = { status: 'queued', waitingOn: 'engineer', note: 'Waiting for the migration engineer to pick this up.', stop: false, claimedBy: '', updated: iso(),
        entries: [{ at: iso(), heading: 'Queued', text: `Migration submitted with ${list.length} reference file(s).` +
          (prev ? `\n\nRe-process run ${self.RunNo} of ${self.FormName} - the previous run on branch ${prev.BranchName} was stopped.` : '') +
          `\n\nSent by Bolt with Fiori from SAP system ${SYSID} client 100 by user ${ME} (serial no. ${self.SerialNo}). (example)` }] };
      syncRow(self); touch(self); hist(self, 'PUSHED', 'CLIENT', { CommitSha: commit });
      messages.push(msg(`${self.FormName}: ${self.PushMsg}`));
      return one(self);
    }
    case 'refreshAll': {
      const open = db.Migration.filter((m) => m.PushStatus === 'PUSHED' && !m.Superseded && m.MigStatus !== 'completed');
      open.forEach((m) => { if (syncRow(m)) hist(m, 'STATUS', 'ENGINEER'); });
      return { body: { value: open.map((m) => shape('Migration', m)) }, messages };
    }
    case 'refreshStatus':
      if (self.PushStatus === 'PUSHED' && syncRow(self)) hist(self, 'STATUS', 'ENGINEER');
      return one(self);
    case 'respond': {
      needPushed();
      const kind = String(p.Kind || '').toLowerCase();
      const text = String(p.Text || '').trim();
      const list = parseFiles(p.FilesJson);
      if (kind === 'confirm') {
        if (sf.stop) fail('This migration is stopped. Resume it first.');
        if (!sf.waitingOn || sf.waitingOn === 'engineer') fail('Nothing is waiting for your confirmation right now.');
      } else if (!text && !list.length) fail('Type your concern first.');
      await wait(500);
      let attached = '';
      if (list.length) {
        const folder = `${self.BranchName}/concerns/${Date.now()}`;
        addFiles(self, list.map((f) => ({ name: f.name, kind: 'ATTACH', size: sizeOf(f.content), path: `${folder}/${f.name}` })), sha());
        self.FilesCount += list.length;
        attached = `\n\nAttached: ${list.map((f) => f.name).join(', ')} (pushed to \`${folder}/\`)`;
      }
      if (kind === 'confirm') {
        const note = `${text}${attached}`.trim();
        Object.assign(sf, { status: 'in_progress', waitingOn: 'engineer', note: '' });
        entry(self, 'Manual activity confirmed', note ? `Client confirmed the manual step is done: ${note}` : 'Client confirmed the manual step is done.');
      } else {
        Object.assign(sf, { status: 'open_for_concerns', waitingOn: 'engineer', note: '' });
        entry(self, { problem: 'Problem reported', question: 'Question', change: 'Change requested' }[kind] || 'Concern raised', `${text}${attached}`.trim());
      }
      syncRow(self); touch(self);
      hist(self, { confirm: 'CONFIRMED', problem: 'PROBLEM', question: 'QUESTION', change: 'CHANGE' }[kind] || 'CONCERN');
      return one(self);
    }
    case 'requestStop': {
      if (self.Superseded) fail(`${self.FormName} (serial no. ${self.SerialNo}) was replaced by a re-process run - work on the newer one.`);
      if (self.MigStatus === 'completed') fail(`${self.FormName} is completed - use Raise a concern for any follow-up.`);
      if (self.Stopped) fail(`${self.FormName} is already stopped.`);
      if (sf) {
        const note = String(p.Reason || '').trim();
        sf.stop = true;
        entry(self, 'Stop requested', note ? `Client requested a stop: ${note}` : 'Client requested a stop. No further migration activity should proceed until resumed.');
        syncRow(self);
      } else {
        self.Stopped = true;
      }
      self.StoppedAt = iso(); touch(self); hist(self, 'STOPPED');
      messages.push(msg(`${self.FormName} stopped. You can resume it, or select it again on the Smart Forms tab for a re-process run.`));
      return one(self);
    }
    case 'resume': {
      if (self.Superseded) fail(`${self.FormName} (serial no. ${self.SerialNo}) was replaced by a re-process run - work on the newer one.`);
      if (!self.Stopped) fail(`${self.FormName} is not stopped.`);
      if (sf) { sf.stop = false; entry(self, 'Resumed', 'Client resumed the migration.'); syncRow(self); } else { self.Stopped = false; }
      touch(self); hist(self, 'RESUMED');
      messages.push(msg(`${self.FormName} resumed.`));
      return one(self);
    }
    case 'saveLegacyDocs': {
      const add = parseFiles(p.FilesJson);
      const ids = String(p.RemoveIds || '').split(',').map((x) => x.trim().toUpperCase()).filter(Boolean);
      if (!add.length && !ids.length) fail('Nothing to save - add or remove a file first.');
      if (add.length) needPushed();
      await wait(500);
      if (add.length) {
        addFiles(self, add.map((f) => ({ name: f.name, kind: 'LEGACY', size: sizeOf(f.content), path: `${self.BranchName}/${f.name}` })), sha());
        self.FilesCount += add.length; hist(self, 'DOCS_ADDED');
      }
      let removed = 0;
      db.MigrationFile.filter((f) => f.MigUuid === self.MigUuid && !f.Removed && ids.includes(f.FileUuid.replace(/-/g, '').toUpperCase()))
        .forEach((f) => { Object.assign(f, { Removed: true, RemovedAt: iso(), RemovedBy: ME }); removed += 1; });
      if (removed) hist(self, 'DOCS_REMOVED');
      touch(self);
      messages.push(msg(`Legacy documents saved: ${add.length} added (pushed to the branch), ${removed} removed from this list (left untouched on the branch).`));
      return one(self);
    }
    case 'aiSummary':
      needPushed();
      await wait(900);
      return { body: { Text: `**${self.FormName} - example AI summary**\n- Prints a ${self.FormDescr.toLowerCase()}: header, partner, item lines with quantity and price.\n- Printed by ${self.DriverProgs || 'a driver program'} (output types ${self.OutputTypes || 'none in NACE'}).\n- 3 windows, one repeating item table, two conditions - ${self.Complexity || 'medium'} complexity.\n- Needs attention: the currency reference of the amount fields, and the logo in SE78.` }, messages };
    default: fail(`Unknown action ${name}`);
  }
  return null;
}

// ---------------------------------------------------------------- $batch
function parseParts(text, boundary) {
  return text.split(`--${boundary}`).slice(1).filter((p) => !p.startsWith('--')).map((p) => p.replace(/^\r?\n/, ''));
}
function splitHead(part) {
  const i = part.search(/\r?\n\r?\n/);
  const head = part.slice(0, i);
  const rest = part.slice(i).replace(/^\r?\n\r?\n/, '');
  return { head, rest };
}
function httpPart(res) {
  const status = res.status || 200;
  const reason = { 200: 'OK', 201: 'Created', 204: 'No Content', 400: 'Bad Request', 403: 'Forbidden', 404: 'Not Found', 405: 'Method Not Allowed', 500: 'Internal Server Error' }[status] || 'OK';
  const headers = ['Content-Type: application/json;odata.metadata=minimal;charset=utf-8', 'OData-Version: 4.0'];
  if (res.messages && res.messages.length) headers.push(`sap-messages: ${JSON.stringify(res.messages)}`);
  const body = status === 204 ? '' : JSON.stringify(res.body || {});
  return `Content-Type: application/http\r\nContent-Transfer-Encoding: binary\r\n${res.contentId ? `Content-ID: ${res.contentId}\r\n` : ''}\r\nHTTP/1.1 ${status} ${reason}\r\n${headers.join('\r\n')}\r\n\r\n${body}\r\n`;
}
async function runRequest(raw, contentId) {
  const { rest } = splitHead(raw);
  const { head: reqHead, rest: reqBody } = splitHead(rest);
  const [method, target] = reqHead.split(/\r?\n/)[0].split(' ');
  try {
    const res = await handle(method, decodeURI(target).replace(/^\/?/, ''), reqBody.trim());
    return { ...res, contentId };
  } catch (e) {
    return { status: e.status || 500, body: { error: { code: 'BOLT', message: e.message } }, contentId };
  }
}
async function batch(body, contentType) {
  const boundary = /boundary=([^;]+)/.exec(contentType)[1];
  const out = [];
  for (const part of parseParts(body, boundary)) {
    const { head, rest } = splitHead(part);
    const cs = /multipart\/mixed;\s*boundary=([^\s;]+)/i.exec(head);
    if (cs) {
      const inner = [];
      for (const p of parseParts(rest, cs[1])) {
        const cid = (/Content-ID:\s*(\S+)/i.exec(splitHead(p).head) || [])[1];
        inner.push(httpPart(await runRequest(p, cid)));
      }
      const b = `changesetresponse_${crypto.randomBytes(4).toString('hex')}`;
      out.push(`Content-Type: multipart/mixed; boundary=${b}\r\n\r\n${inner.map((x) => `--${b}\r\n${x}`).join('')}--${b}--\r\n`);
    } else {
      out.push(httpPart(await runRequest(part)));
    }
  }
  const b = `batchresponse_${crypto.randomBytes(4).toString('hex')}`;
  return { boundary: b, text: `${out.map((x) => `--${b}\r\n${x}`).join('')}--${b}--\r\n` };
}

http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { body += c; });
  req.on('end', async () => {
    try {
      const url = req.url;
      if (url.startsWith(SERVICE)) {
        const rel = url.slice(SERVICE.length);
        const csrf = { 'X-CSRF-Token': 'mock-token', 'OData-Version': '4.0' };
        if (rel.startsWith('$metadata')) { res.writeHead(200, { 'Content-Type': 'application/xml', ...csrf }); res.end(metadata()); return; }
        if (rel.startsWith('$batch')) {
          const out = await batch(body, req.headers['content-type'] || '');
          res.writeHead(200, { 'Content-Type': `multipart/mixed; boundary=${out.boundary}`, ...csrf });
          res.end(out.text);
          return;
        }
        if (req.method === 'HEAD' || rel === '') { res.writeHead(200, csrf); res.end(); return; }
        const r = await handle(req.method, decodeURI(rel), body).catch((e) => ({ status: e.status || 500, body: { error: { message: e.message } } }));
        const headers = { 'Content-Type': 'application/json', ...csrf };
        if (r.messages && r.messages.length) headers['sap-messages'] = JSON.stringify(r.messages);
        res.writeHead(r.status || 200, headers);
        res.end(r.status === 204 ? '' : JSON.stringify(r.body || {}));
        return;
      }
      let file = url.split('?')[0];
      if (file === '/') file = '/index.html';
      const full = path.join(webapp, decodeURIComponent(file));
      if (!full.startsWith(webapp) || !fs.existsSync(full)) { res.writeHead(404); res.end('not found'); return; }
      let content = fs.readFileSync(full);
      if (file === '/index.html') content = Buffer.from(content.toString('utf8').replace('src="resources/sap-ui-core.js"', `src="${UI5}"`));
      res.writeHead(200, { 'Content-Type': MIME[path.extname(full)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
      res.end(content);
    } catch (e) {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end(String(e.stack || e));
    }
  });
}).listen(PORT, () => console.log(`Bolt with Fiori mock: http://localhost:${PORT}/index.html  (example data only)`));
