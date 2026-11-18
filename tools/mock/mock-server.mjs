// Bolt with Fiori - local mock of the ZBOLT_UI OData V4 service, for UI work
// and demos without an SAP backend. No dependencies:
//   node tools/mock/mock-server.mjs        ->  http://localhost:8099/index.html
// Serves app/bolt-fiori/webapp with SAPUI5 from the SAP CDN, answers
// $metadata, $batch (reads and change sets), the CSRF handshake, and every
// action of the real service with plausible behaviour. All data is EXAMPLE
// data (marked as such) - it is not read from any SAP system or repository.
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const PORT = Number(process.env.PORT || 8099);
const here = path.dirname(fileURLToPath(import.meta.url));
const webapp = path.resolve(here, '../../app/bolt-fiori/webapp');
const SERVICE = '/sap/opu/odata4/sap/zbolt_ui_o4/srvd/sap/zbolt_ui/0001/';
const NS = 'com.sap.gateway.srvd.zbolt_ui.v0001';
const UI5 = process.env.UI5_URL || 'https://sapui5.hana.ondemand.com/resources/sap-ui-core.js';

// ----------------------------------------------------------------- model
const T = {
  Migration: {
    keys: ['MigUuid'],
    props: {
      MigUuid: 'Guid', SerialNo: 'Int32', FormName: 'String', FormDescription: 'String', SystemId: 'String',
      SapClient: 'String', BranchName: 'String', FormSlug: 'String', PushStatus: 'String', PushMessage: 'String',
      PushAttempts: 'Int32', PushedAt: 'DateTimeOffset', FilesPushed: 'Int32', CommitSha: 'String', Status: 'String',
      StatusLabel: 'String', WaitingOn: 'String', StatusNote: 'String', StopFlag: 'String', ClaimedBy: 'String',
      StatusUpdated: 'String', StatusSha: 'String', LastSyncAt: 'DateTimeOffset', Complexity: 'String',
      ComplexityText: 'String', Withdrawn: 'String', CreatedBy: 'String', CreatedAt: 'DateTimeOffset',
      ChangedBy: 'String', ChangedAt: 'DateTimeOffset', LocalLastChanged: 'DateTimeOffset',
    },
    nav: { _Log: 'MigrationLog', _File: 'MigrationFile' },
  },
  MigrationLog: {
    keys: ['MigUuid', 'LogUuid'],
    props: { MigUuid: 'Guid', LogUuid: 'Guid', LogSource: 'String', SeqNo: 'Int32', EntryAt: 'String', Heading: 'String', Actor: 'String', LogText: 'String', CreatedAt: 'DateTimeOffset' },
  },
  MigrationFile: {
    keys: ['MigUuid', 'FileUuid'],
    props: { MigUuid: 'Guid', FileUuid: 'Guid', FilePath: 'String', FileName: 'String', Kind: 'String', SizeBytes: 'Int32', PushedAt: 'DateTimeOffset', CreatedBy: 'String' },
  },
  Setup: {
    keys: ['SetupId'],
    props: {
      SetupId: 'String', CustomerName: 'String', GhDestination: 'String', GhOwner: 'String', GhRepo: 'String',
      GhBaseBranch: 'String', GhBranchPrefix: 'String', GhStatus: 'String', GhStatusText: 'String', GhCheckedAt: 'DateTimeOffset',
      AiProvider: 'String', AiModel: 'String', AiDestination: 'String', AiBasePath: 'String', AiMaxTokens: 'Int32', AiKeySet: 'String',
      AiStatus: 'String', AiStatusText: 'String', AiCheckedAt: 'DateTimeOffset', FormPrefix1: 'String', FormPrefix2: 'String',
      CountVolume: 'String', AdminUsers: 'String', CreatedBy: 'String', CreatedAt: 'DateTimeOffset', ChangedBy: 'String',
      ChangedAt: 'DateTimeOffset', LocalLastChanged: 'DateTimeOffset',
    },
  },
  SourceSystem: {
    keys: ['SystemId'],
    props: {
      SystemId: 'String', Description: 'String', SapClient: 'String', Destination: 'String', ServicePath: 'String', BaseUrl: 'String',
      IsLocal: 'String', IsDefault: 'String', SortOrder: 'Int32', Status: 'String', StatusText: 'String', CheckedAt: 'DateTimeOffset',
      CreatedBy: 'String', CreatedAt: 'DateTimeOffset', ChangedBy: 'String', ChangedAt: 'DateTimeOffset', LocalLastChanged: 'DateTimeOffset',
    },
  },
  SmartForm: {
    keys: ['SystemId', 'FormName'],
    props: {
      SystemId: 'String', FormName: 'String', Description: 'String', DevPackage: 'String', CreatedBy: 'String', CreatedOn: 'String',
      ChangedBy: 'String', ChangedOn: 'String', DriverProgram: 'String', OutputTypes: 'String', InMigration: 'Boolean',
      MigrationSerial: 'Int32', MigrationStatus: 'String', MigUuid: 'Guid', Message: 'String',
    },
  },
};
const ACTIONS = {
  Migration: {
    commitSelection: { static: true, params: { SystemId: 'String', Selection: 'String' }, returns: 'collection' },
    refreshAll: { static: true, params: {}, returns: 'collection' },
    importFromGitHub: { static: true, params: {}, returns: 'collection' },
    pushToGitHub: { params: {}, returns: 'self' },
    refreshStatus: { params: {}, returns: 'self' },
    confirmManual: { params: { Note: 'String', FileName: 'String', FileContent: 'String' }, returns: 'self' },
    raiseConcern: { params: { Kind: 'String', Text: 'String', FileName: 'String', FileContent: 'String' }, returns: 'self' },
    setStop: { params: { StopRequested: 'Boolean', Note: 'String' }, returns: 'self' },
    addReferenceFile: { params: { FileName: 'String', FileContent: 'String' }, returns: 'self' },
    withdraw: { params: { DeleteBranch: 'Boolean', Reason: 'String' }, returns: 'self' },
    aiSummary: { params: {}, returns: 'text' },
  },
  Setup: {
    initialize: { static: true, params: {}, returns: 'self' },
    testGitHub: { params: {}, returns: 'self' },
    testAi: { params: {}, returns: 'self' },
    setAiKey: { params: { ApiKey: 'String' }, returns: 'self' },
  },
  SourceSystem: { testConnection: { params: {}, returns: 'self' } },
};

function metadata() {
  const types = Object.entries(T).map(([set, t]) => {
    const props = Object.entries(t.props).map(([n, ty]) =>
      `<Property Name="${n}" Type="Edm.${ty}"${t.keys.includes(n) ? ' Nullable="false"' : ''}${ty === 'DateTimeOffset' ? ' Precision="7"' : ''}/>`).join('');
    const nav = Object.entries(t.nav || {}).map(([n, target]) =>
      `<NavigationProperty Name="${n}" Type="Collection(${NS}.${target}Type)" Partner="_Migration"/>`).join('');
    const back = set === 'MigrationLog' || set === 'MigrationFile' ? `<NavigationProperty Name="_Migration" Type="${NS}.MigrationType" Nullable="false" Partner="${set === 'MigrationLog' ? '_Log' : '_File'}"/>` : '';
    return `<EntityType Name="${set}Type"><Key>${t.keys.map((k) => `<PropertyRef Name="${k}"/>`).join('')}</Key>${props}${nav}${back}</EntityType>`;
  }).join('');
  const text = `<ComplexType Name="ZA_BOLT_TEXT_RType"><Property Name="ResultText" Type="Edm.String"/></ComplexType>`;
  const actions = Object.entries(ACTIONS).flatMap(([set, acts]) => Object.entries(acts).map(([name, a]) => {
    const bind = a.static ? `Collection(${NS}.${set}Type)` : `${NS}.${set}Type`;
    const params = Object.entries(a.params).map(([n, ty]) => `<Parameter Name="${n}" Type="Edm.${ty}"/>`).join('');
    let ret = `<ReturnType Type="${NS}.${set}Type" Nullable="false"/>`;
    if (a.returns === 'collection') ret = `<ReturnType Type="Collection(${NS}.${set}Type)" Nullable="false"/>`;
    if (a.returns === 'text') ret = `<ReturnType Type="${NS}.ZA_BOLT_TEXT_RType" Nullable="false"/>`;
    return `<Action Name="${name}" IsBound="true"><Parameter Name="_it" Type="${bind}" Nullable="false"/>${params}${ret}</Action>`;
  })).join('');
  const sets = Object.keys(T).map((set) => {
    const nav = Object.entries(T[set].nav || {}).map(([n, target]) => `<NavigationPropertyBinding Path="${n}" Target="${target}"/>`).join('');
    const back = set === 'MigrationLog' || set === 'MigrationFile' ? '<NavigationPropertyBinding Path="_Migration" Target="Migration"/>' : '';
    return `<EntitySet Name="${set}" EntityType="${NS}.${set}Type">${nav}${back}</EntitySet>`;
  }).join('');
  return `<?xml version="1.0" encoding="utf-8"?><edmx:Edmx Version="4.0" xmlns:edmx="http://docs.oasis-open.org/odata/ns/edmx"><edmx:DataServices><Schema Namespace="${NS}" xmlns="http://docs.oasis-open.org/odata/ns/edm">${types}${text}${actions}<EntityContainer Name="Container">${sets}</EntityContainer></Schema></edmx:DataServices></edmx:Edmx>`;
}

// ------------------------------------------------------------------ data
const iso = (d = new Date()) => d.toISOString();
const ago = (h) => new Date(Date.now() - h * 3600e3);
const uuid = () => crypto.randomUUID();
const D = '—';
const db = {
  Setup: [{
    SetupId: 'DEFAULT', CustomerName: 'Dangote (example data)', GhDestination: 'ZBOLT_GITHUB', GhOwner: 'VernasoftTechie',
    GhRepo: 'Smartform-Adobe-Migration', GhBaseBranch: 'main', GhBranchPrefix: 'vernasofttechie', GhStatus: 'OK',
    GhStatusText: 'Connected as VernasoftTechie: VernasoftTechie/Smartform-Adobe-Migration (default branch main), write access confirmed. (example)',
    GhCheckedAt: iso(ago(1)), AiProvider: 'ANTHROPIC', AiModel: 'claude-sonnet-5-5', AiDestination: 'ZBOLT_AI', AiBasePath: '/v1',
    AiMaxTokens: 2000, AiKeySet: 'X', AiStatus: 'OK', AiStatusText: 'Connection OK - ANTHROPIC (claude-sonnet-5-5) responded: OK (example)',
    AiCheckedAt: iso(ago(1)), FormPrefix1: 'Z', FormPrefix2: 'Y', CountVolume: 'X', AdminUsers: '', CreatedBy: 'BOLTADMIN',
    CreatedAt: iso(ago(400)), ChangedBy: 'BOLTADMIN', ChangedAt: iso(ago(1)), LocalLastChanged: iso(ago(1)),
  }],
  SourceSystem: [
    { SystemId: 'DEV', Description: 'This system (S4D)', SapClient: '100', Destination: '', ServicePath: SERVICE, BaseUrl: 'https://s4d.example:44300', IsLocal: 'X', IsDefault: 'X', SortOrder: 10, Status: 'OK', StatusText: 'Reads this system directly (S4D client 100) - 14 custom Smart Form(s) visible. (example)', CheckedAt: iso(ago(1)) },
    { SystemId: 'QA', Description: 'QA system', SapClient: '200', Destination: 'ZBOLT_QA', ServicePath: SERVICE, BaseUrl: 'https://s4q.example:44300', IsLocal: '', IsDefault: '', SortOrder: 20, Status: 'OK', StatusText: 'Connected to QA client 200 - the Bolt service answered, 13 custom Smart Form(s) visible. (example)', CheckedAt: iso(ago(2)) },
    { SystemId: 'PRD', Description: 'Production', SapClient: '300', Destination: 'ZBOLT_PRD', ServicePath: SERVICE, BaseUrl: 'https://s4p.example:44300', IsLocal: '', IsDefault: '', SortOrder: 30, Status: 'ERROR', StatusText: 'System PRD answered HTTP 401 Unauthorized. Logon failed - check the user/password in the SM59 destination. (example)', CheckedAt: iso(ago(3)) },
  ],
  forms: [
    ['YMM_PO_SMARTFORM', 'Purchase order', 'ZMM', 'YMM_PO_PROGRAM', 'EF/NEU'],
    ['ZMMCG_PO_SF', 'Purchase order (CG)', 'ZMM', 'ZCGMMPOP001', 'EF/ZCG1'],
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
  Migration: [],
  MigrationLog: [],
  MigrationFile: [],
};

function addMigration(m, entries, files) {
  const row = {
    MigUuid: uuid(), SerialNo: 0, FormDescription: '', SystemId: 'DEV', SapClient: '100', FormSlug: m.FormName.toLowerCase(),
    BranchName: `vernasofttechie-${m.FormName.toLowerCase()}`, PushStatus: 'PUSHED', PushMessage: '', PushAttempts: 1, PushedAt: iso(ago(m.hours ?? 10)),
    FilesPushed: (files || []).length, CommitSha: crypto.randomBytes(20).toString('hex'), Status: 'queued', StatusLabel: 'Queued', WaitingOn: 'engineer',
    StatusNote: '', StopFlag: '', ClaimedBy: '', StatusUpdated: iso(ago(1)), StatusSha: crypto.randomBytes(20).toString('hex'), LastSyncAt: iso(ago(0.2)),
    Complexity: 'medium', ComplexityText: '3 window(s), 1 table/loop section(s), 2 condition(s), 1 language(s), 1 embedded code node(s), 12 interface parameter(s).',
    Withdrawn: '', CreatedBy: 'OPERATOR1', CreatedAt: iso(ago(m.hours ?? 10)), ChangedBy: 'OPERATOR1', ChangedAt: iso(ago(1)), LocalLastChanged: iso(ago(1)), ...m,
  };
  db.Migration.push(row);
  (entries || []).forEach(([at, heading, actor, text], i) => db.MigrationLog.push({
    MigUuid: row.MigUuid, LogUuid: uuid(), LogSource: 'STATUS', SeqNo: i + 1, EntryAt: at, Heading: heading, Actor: actor, LogText: text, CreatedAt: iso(),
  }));
  db.MigrationLog.push({ MigUuid: row.MigUuid, LogUuid: uuid(), LogSource: 'APP', SeqNo: 0, EntryAt: row.CreatedAt, Heading: 'Selected for migration', Actor: 'client', LogText: `Selected and committed by SAP user OPERATOR1 from system DEV client 100 (serial no. ${row.SerialNo}).`, CreatedAt: row.CreatedAt });
  (files || []).forEach(([name, kind, size]) => db.MigrationFile.push({
    MigUuid: row.MigUuid, FileUuid: uuid(), FilePath: `${row.BranchName}/${name}`, FileName: name, Kind: kind, SizeBytes: size, PushedAt: row.PushedAt, CreatedBy: 'OPERATOR1',
  }));
  return row;
}

const std = (form) => [[`${form}.md`, 'SNAPSHOT', 18450], [`${form.toLowerCase()}.xml`, 'XML', 412300], [`driver_${form}_DRV.txt`, 'DRIVER', 22110]];
addMigration({ SerialNo: 1, FormName: 'ZCGSD_INVOICE', FormDescription: 'Sales invoice', Status: 'completed', StatusLabel: 'Migration Completed', WaitingOn: '', ClaimedBy: 'Window-1', Complexity: 'high', hours: 1150, StatusUpdated: iso(ago(1100)) },
  [[iso(ago(1150)), 'Queued', 'app', 'Migration submitted with 3 reference file(s). (example)'], [iso(ago(1149)), 'Picked up', 'engineer', 'Window-1 picked this migration up.'], [iso(ago(1100)), 'Migration completed', 'engineer', 'Closed on your confirmation that the layout activated and everything looks right.']], std('ZCGSD_INVOICE'));
addMigration({ SerialNo: 2, FormName: 'ZFING_CUST_ACT_SUM', FormDescription: 'Customer account summary', Status: 'waiting_manual', StatusLabel: `Waiting ${D} Manual Activity`, WaitingOn: 'operator', ClaimedBy: 'Window-1', StatusNote: 'Context tree built and pushed - pull this branch and check it imports cleanly, then confirm or report the exact error.', hours: 1000 },
  [[iso(ago(1000)), 'Queued', 'app', 'Migration submitted with 7 reference file(s). (example)'], [iso(ago(999)), 'Interface prepared', 'engineer', 'The form interface has been prepared from your reference export:\n- 19 custom import parameters and 5 tables\n- 13 global data fields\n- `LV_WAERK` added as the currency key'], [iso(ago(998)), 'Context tree built', 'engineer', 'Please:\n1. Pull this branch onto the form in SFP.\n2. Check the Context tree shows all **24 nodes**.\n3. Confirm, or report the exact error.']], std('ZFING_CUST_ACT_SUM'));
addMigration({ SerialNo: 3, FormName: 'ZMM_PO_DEMO', FormDescription: 'Purchase order demo', Status: 'waiting_manual', StatusLabel: `Waiting ${D} Manual Activity`, WaitingOn: 'operator', ClaimedBy: 'Window-1', StatusNote: 'Layout with page continuation pushed - pull it, activate, and preview with a purchase order of more than 29 items (and a short one), then confirm or report what you see.', Complexity: 'low', hours: 950 },
  [[iso(ago(950)), 'Queued', 'app', 'Migration submitted with 2 reference file(s). (example)'], [iso(ago(949)), 'Picked up', 'engineer', 'Window-1 picked this migration up.'], [iso(ago(948)), 'Manual activity confirmed', 'client', 'Client confirmed the manual step is done.'], [iso(ago(947)), 'Page continuation built', 'engineer', '**How a long purchase order prints now**\n- Every page shows the title and the bordered main window.\n- Item rows flow from page to page, 29 rows per page.\n\nPreview with a purchase order of **more than 29 items**.']], std('ZMM_PO_DEMO'));
addMigration({ SerialNo: 4, FormName: 'ZMMET_PO_SF', FormDescription: 'Purchase order (ET)', Status: 'layout_in_progress', StatusLabel: 'Form Design In Progress', WaitingOn: 'engineer', ClaimedBy: 'Window-4', hours: 60 },
  [[iso(ago(60)), 'Queued', 'app', 'Migration submitted with 6 reference file(s). (example)'], [iso(ago(59)), 'Picked up', 'engineer', 'Window-4 picked this migration up.'], [iso(ago(20)), 'Layout started', 'engineer', 'The Context imported cleanly; layout in progress.']], std('ZMMET_PO_SF'));

// --------------------------------------------------------------- helpers
function smartForms(system) {
  return db.forms.map(([FormName, Description, DevPackage, DriverProgram, OutputTypes], i) => {
    const mig = db.Migration.find((m) => m.FormName === FormName && m.Withdrawn !== 'X');
    return {
      SystemId: system, FormName, Description, DevPackage, CreatedBy: 'ABAP07', CreatedOn: '20150325', ChangedBy: 'C.KKUMAR',
      ChangedOn: `2026${String((i % 9) + 1).padStart(2, '0')}15`, DriverProgram, OutputTypes, InMigration: !!mig,
      MigrationSerial: mig ? mig.SerialNo : 0,
      MigrationStatus: mig ? (mig.PushStatus === 'PENDING' ? 'Sending to GitHub' : mig.PushStatus === 'FAILED' ? 'Sending failed - see Migration' : mig.StatusLabel) : '',
      MigUuid: mig ? mig.MigUuid : null, Message: '',
    };
  }).filter((f) => system !== 'QA' || f.FormName !== 'YFI_CHEQUE');
}
function statusLog(mig, heading, actor, text) {
  const seq = db.MigrationLog.filter((l) => l.MigUuid === mig.MigUuid && l.LogSource === 'STATUS').length + 1;
  db.MigrationLog.push({ MigUuid: mig.MigUuid, LogUuid: uuid(), LogSource: 'STATUS', SeqNo: seq, EntryAt: iso(), Heading: heading, Actor: actor, LogText: text, CreatedAt: iso() });
}
function appLog(mig, heading, text) {
  db.MigrationLog.push({ MigUuid: mig.MigUuid, LogUuid: uuid(), LogSource: 'APP', SeqNo: 0, EntryAt: iso(), Heading: heading, Actor: 'app', LogText: text, CreatedAt: iso() });
}
class Http extends Error { constructor(status, message) { super(message); this.status = status; } }
const msg = (text, severity = 1) => ({ code: 'BOLT/000', message: text, numericSeverity: severity, target: '', transition: true });

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
function find(set, keys) {
  const row = db[set].find((r) => Object.entries(keys).every(([k, v]) => String(r[k]) === String(v)));
  if (!row) throw new Http(404, `${set} not found`);
  return row;
}
function shape(set, row, expand) {
  const out = {};
  Object.keys(T[set].props).forEach((p) => { out[p] = row[p] === undefined ? null : row[p]; });
  if (set === 'Migration' && expand) {
    if (expand.includes('_Log')) out._Log = db.MigrationLog.filter((l) => l.MigUuid === row.MigUuid).map((l) => shape('MigrationLog', l));
    if (expand.includes('_File')) out._File = db.MigrationFile.filter((f) => f.MigUuid === row.MigUuid).map((f) => shape('MigrationFile', f));
  }
  return out;
}

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
    if (first.keys) {
      const row = first.set === 'Setup' || first.set === 'SourceSystem' || first.set === 'Migration' ? find(first.set, first.keys) : null;
      return { body: shape(first.set, row, q.$expand || '') };
    }
    let rows;
    if (first.set === 'SmartForm') {
      const sys = (/SystemId eq '([^']*)'/.exec(q.$filter || '') || [])[1] || 'DEV';
      if (sys === 'PRD') rows = [{ SystemId: 'PRD', FormName: '*ERROR*', Message: 'System PRD answered HTTP 401 Unauthorized. Logon failed - check the user/password in the SM59 destination. (example)' }];
      else rows = smartForms(sys);
      await new Promise((r) => setTimeout(r, 400));
    } else {
      rows = db[first.set] || [];
    }
    if (q.$orderby) {
      const [field, dir] = q.$orderby.split(' ');
      rows = [...rows].sort((a, b) => (a[field] > b[field] ? 1 : a[field] < b[field] ? -1 : 0) * (dir === 'desc' ? -1 : 1));
    }
    const count = rows.length;
    const skip = Number(q.$skip || 0);
    const top = q.$top ? Number(q.$top) : rows.length;
    const value = rows.slice(skip, skip + top).map((r) => shape(first.set, r));
    return { body: { ...(q.$count === 'true' ? { '@odata.count': count } : {}), value } };
  }
  if (method === 'PATCH') {
    const row = find(first.set, first.keys);
    Object.assign(row, JSON.parse(body || '{}'), { ChangedAt: iso() });
    return { body: shape(first.set, row) };
  }
  if (method === 'POST' && first.set === 'SourceSystem') {
    const data = JSON.parse(body || '{}');
    if (db.SourceSystem.some((s) => s.SystemId === data.SystemId)) throw new Http(400, `System ${data.SystemId} already exists`);
    const row = { Status: '', StatusText: '', CheckedAt: null, CreatedBy: 'BOLTADMIN', CreatedAt: iso(), ...data };
    db.SourceSystem.push(row);
    return { status: 201, body: shape('SourceSystem', row) };
  }
  if (method === 'DELETE') {
    const row = find(first.set, first.keys);
    db[first.set].splice(db[first.set].indexOf(row), 1);
    return { status: 204 };
  }
  throw new Http(405, `${method} ${url} not supported by the mock`);
}

async function runAction(set, keys, name, p, messages) {
  const self = keys ? find(set, keys) : null;
  const one = (row, s = set) => ({ body: shape(s, row), messages });
  if (set === 'Setup') {
    if (name === 'initialize') return one(db.Setup[0]);
    if (name === 'testGitHub') { Object.assign(self, { GhStatus: 'OK', GhCheckedAt: iso() }); messages.push(msg(self.GhStatusText)); return one(self); }
    if (name === 'testAi') {
      if (self.AiProvider === 'NONE') Object.assign(self, { AiStatus: 'OK', AiStatusText: 'Built-in (no AI provider) - nothing to connect.' });
      else Object.assign(self, { AiStatus: 'OK', AiStatusText: `Connection OK - ${self.AiProvider} (${self.AiModel || 'default'}) responded: OK (example)` });
      self.AiCheckedAt = iso(); messages.push(msg(self.AiStatusText)); return one(self);
    }
    if (name === 'setAiKey') { Object.assign(self, { AiKeySet: p.ApiKey ? 'X' : '', AiStatus: '', AiStatusText: p.ApiKey ? 'API key saved - run Test connection.' : 'API key removed.' }); return one(self); }
  }
  if (set === 'SourceSystem' && name === 'testConnection') {
    await new Promise((r) => setTimeout(r, 500));
    if (self.IsLocal === 'X') Object.assign(self, { Status: 'OK', StatusText: 'Reads this system directly (S4D client 100) - 14 custom Smart Form(s) visible. (example)' });
    else if (!self.Destination) Object.assign(self, { Status: 'ERROR', StatusText: `System ${self.SystemId} has no SM59 destination - set one, or mark it "This system".` });
    else if (self.SystemId === 'PRD') Object.assign(self, { Status: 'ERROR', StatusText: 'System PRD answered HTTP 401 Unauthorized. Logon failed - check the user/password in the SM59 destination. (example)' });
    else Object.assign(self, { Status: 'OK', StatusText: `Connected to ${self.SystemId} - the Bolt service answered. (example)` });
    self.CheckedAt = iso();
    messages.push(msg(self.StatusText, self.Status === 'OK' ? 1 : 3));
    return one(self);
  }
  if (set !== 'Migration') throw new Http(400, `Unknown action ${name}`);

  switch (name) {
    case 'commitSelection': {
      let serial = Math.max(0, ...db.Migration.map((m) => m.SerialNo));
      const created = [];
      p.Selection.split('\n').filter(Boolean).forEach((line) => {
        const [FormName, desc = ''] = line.split('|');
        const existing = db.Migration.find((m) => m.FormName === FormName && m.Withdrawn !== 'X');
        if (existing) { messages.push(msg(`${FormName} is already in migration (serial no. ${existing.SerialNo}) - skipped.`, 3)); return; }
        serial += 1;
        const row = addMigration({ SerialNo: serial, FormName, FormDescription: desc.trim(), SystemId: p.SystemId, PushStatus: 'PENDING', PushAttempts: 0, StatusLabel: 'Sending to GitHub', Status: '', WaitingOn: '', StatusUpdated: '', hours: 0 }, [], []);
        created.push(row);
      });
      return { body: { value: created.map((r) => shape('Migration', r)) }, messages };
    }
    case 'pushToGitHub': {
      await new Promise((r) => setTimeout(r, 1500));
      if (self.FormName === 'ZHR_PAYSLIP') {
        Object.assign(self, { PushStatus: 'FAILED', PushAttempts: self.PushAttempts + 1, StatusLabel: 'Sending failed', PushMessage: 'Smart Form XML export failed (form ZHR_PAYSLIP is locked by user HRDEV) - example of a failed send.' });
        appLog(self, 'Sending to GitHub failed', self.PushMessage);
        messages.push(msg(`${self.FormName}: ${self.PushMessage}`, 3));
        return one(self);
      }
      const files = std(self.FormName);
      files.forEach(([n, k, s]) => db.MigrationFile.push({ MigUuid: self.MigUuid, FileUuid: uuid(), FilePath: `${self.BranchName}/${n}`, FileName: n, Kind: k, SizeBytes: s, PushedAt: iso(), CreatedBy: 'OPERATOR1' }));
      Object.assign(self, { PushStatus: 'PUSHED', PushAttempts: self.PushAttempts + 1, PushedAt: iso(), FilesPushed: files.length, Status: 'queued', StatusLabel: 'Queued', WaitingOn: 'engineer', StatusNote: 'Waiting for the migration engineer to pick this up.', StatusUpdated: iso(), Complexity: ['low', 'medium', 'high'][self.SerialNo % 3] });
      statusLog(self, 'Queued', 'app', `Migration submitted with ${files.length} reference file(s).\n\nSent by Bolt with Fiori from SAP system ${self.SystemId} (example).`);
      appLog(self, 'Sent to GitHub', `Created branch ${self.BranchName} and pushed ${files.length} reference file(s) and the status file in one commit. (example)`);
      messages.push(msg(`${self.FormName} sent to GitHub.`));
      return one(self);
    }
    case 'refreshAll': return { body: { value: db.Migration.filter((m) => m.PushStatus === 'PUSHED' && m.Withdrawn !== 'X').map((m) => shape('Migration', m)) }, messages };
    case 'importFromGitHub': messages.push(msg('No migration branches on GitHub that this app does not know yet.', 2)); return { body: { value: [] }, messages };
    case 'refreshStatus': self.LastSyncAt = iso(); return one(self);
    case 'confirmManual': {
      if (self.StopFlag === 'X') throw new Http(400, 'This migration is stopped. Resume it first.');
      if (!self.WaitingOn || self.WaitingOn === 'engineer') throw new Http(400, 'Nothing is waiting for your confirmation right now.');
      Object.assign(self, { Status: 'in_progress', StatusLabel: 'In Progress', WaitingOn: 'engineer', StatusNote: '', StatusUpdated: iso() });
      statusLog(self, 'Manual activity confirmed', 'client', p.Note ? `Client confirmed the manual step is done: ${p.Note}` : 'Client confirmed the manual step is done.');
      appLog(self, 'Confirmed the manual step', p.Note || 'Confirmed without a note.');
      messages.push(msg('Confirmation submitted - the engineer has been notified and the migration is now In Progress.'));
      return one(self);
    }
    case 'raiseConcern': {
      if (!p.Text && !p.FileContent) throw new Http(400, 'Type your concern first.');
      const heading = { problem: 'Problem reported', question: 'Question', change: 'Change requested' }[p.Kind] || 'Concern raised';
      Object.assign(self, { Status: 'open_for_concerns', StatusLabel: `Open ${D} Awaiting Review`, WaitingOn: 'engineer', StatusNote: '', StatusUpdated: iso() });
      statusLog(self, heading, 'client', p.Text + (p.FileName ? `\n\nAttached: ${p.FileName}` : ''));
      messages.push(msg('Submitted - the engineer has been notified.'));
      return one(self);
    }
    case 'setStop': {
      self.StopFlag = p.StopRequested ? 'X' : '';
      self.StatusUpdated = iso();
      statusLog(self, p.StopRequested ? 'Stop requested' : 'Resumed', 'client', p.StopRequested ? (p.Note ? `Client requested a stop: ${p.Note}` : 'Client requested a stop.') : 'Client resumed the migration.');
      return one(self);
    }
    case 'addReferenceFile':
      db.MigrationFile.push({ MigUuid: self.MigUuid, FileUuid: uuid(), FilePath: `${self.BranchName}/${p.FileName}`, FileName: p.FileName, Kind: 'ATTACH', SizeBytes: Math.round((p.FileContent || '').length * 0.75), PushedAt: iso(), CreatedBy: 'OPERATOR1' });
      appLog(self, 'Attached a reference file', `${p.FileName} pushed to ${self.BranchName}/${p.FileName}.`);
      return one(self);
    case 'withdraw':
      Object.assign(self, { Withdrawn: 'X', PushStatus: 'WITHDRAWN', StatusLabel: 'Withdrawn' });
      appLog(self, 'Withdrawn', `Withdrawn by BOLTADMIN.${p.DeleteBranch ? ` Branch ${self.BranchName} deleted on GitHub.` : ''} ${p.Reason || ''}`);
      return one(self);
    case 'aiSummary':
      await new Promise((r) => setTimeout(r, 800));
      return { body: { ResultText: `**${self.FormName} - example AI summary**\n- Prints a purchase order: header, vendor, item lines with quantity and price.\n- Called by driver program from NACE output type EF/NEU.\n- 3 windows, one repeating item table, one condition - medium complexity.\n- Needs attention: currency reference for the amount fields, and the logo in SE78.` }, messages };
    default: throw new Http(400, `Unknown action ${name}`);
  }
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
  const reason = { 200: 'OK', 201: 'Created', 204: 'No Content', 400: 'Bad Request', 404: 'Not Found', 405: 'Method Not Allowed', 500: 'Internal Server Error' }[status] || 'OK';
  const headers = ['Content-Type: application/json;odata.metadata=minimal;charset=utf-8', 'OData-Version: 4.0'];
  if (res.messages && res.messages.length) headers.push(`sap-messages: ${JSON.stringify(res.messages)}`);
  const body = status === 204 ? '' : JSON.stringify(res.body || {});
  return `Content-Type: application/http\r\nContent-Transfer-Encoding: binary\r\n${res.contentId ? `Content-ID: ${res.contentId}\r\n` : ''}\r\nHTTP/1.1 ${status} ${reason}\r\n${headers.join('\r\n')}\r\n\r\n${body}\r\n`;
}
async function runRequest(raw, contentId) {
  const { head, rest } = splitHead(raw);
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

// ---------------------------------------------------------------- server
const MIME = { '.js': 'application/javascript', '.json': 'application/json', '.xml': 'application/xml', '.css': 'text/css', '.properties': 'text/plain; charset=utf-8', '.html': 'text/html; charset=utf-8' };
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
      if (file === '/' ) file = '/index.html';
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
