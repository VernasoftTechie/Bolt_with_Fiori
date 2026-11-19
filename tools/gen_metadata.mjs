// Generates the abapGit metadata (.xml / .baseinfo) for every source file in
// src/, using the exact shapes confirmed on real systems (ZRAP_MT, VS-Tower,
// ZHR_ESS_V1 - see docs/05_build_notes.md). Re-run after adding or renaming
// an object:  node tools/gen_metadata.mjs   (DDIC: node tools/gen_ddic.mjs first)
// Rules it enforces (Bolt Playbook 5.4): .xml files carry a UTF-8 BOM, source
// files do not; every DDLS has a .baseinfo; object names fit SAP's limits and
// the DIL naming policy (docs/06_naming.md).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const src = path.join(root, 'src');
const BOM = '﻿';
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const files = fs.readdirSync(src);
const read = (f) => fs.readFileSync(path.join(src, f), 'utf8');
const write = (f, text) => fs.writeFileSync(path.join(src, f), text, 'utf8');
const problems = [];
const wrap = (serializer, body) =>
  `${BOM}<?xml version="1.0" encoding="utf-8"?>
<abapGit version="v1.0.0" serializer="${serializer}" serializer_version="v1.0.0">
 <asx:abap xmlns:asx="http://www.sap.com/abapxml" version="1.0">
  <asx:values>
${body}
  </asx:values>
 </asx:abap>
</abapGit>
`;

// ---- source files must not carry a BOM ------------------------------------
for (const f of files) {
  if (/\.(abap|asddls|asbdef|srvdsrv)$/.test(f)) {
    const t = read(f);
    if (t.charCodeAt(0) === 0xfeff) { write(f, t.slice(1)); console.log(`removed BOM from ${f}`); }
  }
}

// ---- CDS (DDLS) -------------------------------------------------------------
for (const f of files.filter((x) => x.endsWith('.ddls.asddls'))) {
  const name = f.replace('.ddls.asddls', '').toUpperCase();
  const text = read(f);
  const label = (/@EndUserText\.label:\s*'([^']*)'/.exec(text) || [])[1] || name;
  let type;
  if (/define\s+abstract\s+entity/i.test(text)) type = 'A';
  else if (/define\s+custom\s+entity/i.test(text)) type = 'C';
  else if (/as\s+projection\s+on/i.test(text)) type = 'P';
  else type = 'W';
  if (name.length > 30) problems.push(`${name}: CDS name longer than 30`);
  if (label.length > 60) problems.push(`${name}: label longer than 60`);
  write(`${f.replace('.asddls', '.xml')}`, wrap('LCL_OBJECT_DDLS', `   <DDLS>
    <DDLNAME>${name}</DDLNAME>
    <DDLANGUAGE>E</DDLANGUAGE>
    <DDTEXT>${esc(label)}</DDTEXT>
    <SOURCE_TYPE>${type}</SOURCE_TYPE>
   </DDLS>`));

  const from = [...text.matchAll(/(?:select\s+from|projection\s+on)\s+([A-Za-z0-9_\/]+)/gi)].map((m) => m[1].toUpperCase());
  const assoc = [...text.matchAll(/(?:composition\s*\[[^\]]*\]\s*of|association\s+(?:to\s+parent\s+|\[[^\]]*\]\s*to\s+|to\s+))\s*([A-Za-z0-9_\/]+)/gi)]
    .map((m) => m[1].toUpperCase());
  const redirected = [...text.matchAll(/redirected\s+to\s+(?:composition\s+child\s+|parent\s+)?([A-Za-z0-9_\/]+)/gi)].map((m) => m[1].toUpperCase());
  const baseinfo = { BASEINFO: { FROM: [...new Set(from)] } };
  const associated = [...new Set([...assoc, ...redirected])].sort();
  if (associated.length) baseinfo.BASEINFO.ASSOCIATED = associated;
  if (type === 'P') baseinfo.BASEINFO.BASE = [...new Set(from)];
  write(`${f.replace('.asddls', '.baseinfo')}`, JSON.stringify(baseinfo, null, 2) + '\n');
}

// ---- behaviour definitions (BDEF) - shape of ZI_RAP_MT_HDR.bdef.xml --------
const bdefText = {
  ZAB_CDS_I_BOLT_MIG: 'Bolt - migration behavior',
  ZAB_CDS_C_BOLT_MIG: 'Bolt - migration behavior (projection)',
  ZAB_CDS_I_BOLT_SETUP: 'Bolt - setup behavior',
  ZAB_CDS_C_BOLT_SETUP: 'Bolt - setup behavior (projection)',
  ZAB_CDS_I_BOLT_LIB: 'Bolt - global library behavior',
  ZAB_CDS_C_BOLT_LIB: 'Bolt - global library behavior (projection)',
};
for (const f of files.filter((x) => x.endsWith('.bdef.asbdef'))) {
  const name = f.replace('.bdef.asbdef', '').toUpperCase();
  const low = name.toLowerCase();
  write(`${low}.bdef.xml`, wrap('LCL_OBJECT_BDEF', `   <BDEF>
    <NAME>${name}</NAME>
    <TYPE>BDEF/BDO</TYPE>
    <DESCRIPTION>${esc(bdefText[name] || name)}</DESCRIPTION>
    <DESCRIPTION_TEXT_LIMIT>60</DESCRIPTION_TEXT_LIMIT>
    <LANGUAGE>EN</LANGUAGE>
    <LINKS>
     <item>
      <HREF>./${low}/source/main/versions</HREF>
      <REL>http://www.sap.com/adt/relations/versions</REL>
      <TITLE>Historic versions</TITLE>
     </item>
     <item>
      <HREF>/sap/bc/adt/repository/informationsystem/abaplanguageversions?uri=%2Fsap%2Fbc%2Fadt%2Fbo%2Fbehaviordefinitions%2F${low}</HREF>
      <REL>http://www.sap.com/adt/relations/informationsystem/abaplanguageversions</REL>
      <TYPE>application/vnd.sap.adt.nameditems.v1+xml</TYPE>
      <TITLE>Allowed ABAP language versions</TITLE>
     </item>
     <item>
      <HREF>./${low}/source/main</HREF>
      <REL>http://www.sap.com/adt/relations/source</REL>
      <TYPE>text/plain</TYPE>
      <TITLE>Source Content</TITLE>
     </item>
     <item>
      <HREF>./${low}/source/main</HREF>
      <REL>http://www.sap.com/adt/relations/source</REL>
      <TYPE>text/html</TYPE>
      <TITLE>Source Content (HTML)</TITLE>
     </item>
    </LINKS>
    <MASTER_LANGUAGE>EN</MASTER_LANGUAGE>
    <ABAP_LANGU_VERSION>X</ABAP_LANGU_VERSION>
    <SOURCE_URI>./${low}/source/main</SOURCE_URI>
    <SOURCE_TYPE>ABAP_SOURCE</SOURCE_TYPE>
    <SOURCE_FIXED_POINT_ARITHMETIC>true</SOURCE_FIXED_POINT_ARITHMETIC>
    <SOURCE_UNICODE_CHECKS_ACTIVE>true</SOURCE_UNICODE_CHECKS_ACTIVE>
   </BDEF>`));
}

// ---- classes (CLAS) ------------------------------------------------------
for (const f of files.filter((x) => /^[a-z0-9_]+\.clas\.abap$/.test(x))) {
  const name = f.replace('.clas.abap', '').toUpperCase();
  const text = read(f);
  const descr = ((/shorttext synchronized">([^<]*)</.exec(text) || [])[1] || name).slice(0, 60);
  const forBehavior = /FOR BEHAVIOR OF\s+([A-Za-z0-9_]+)/i.exec(text);
  const isException = /INHERITING FROM\s+cx_/i.test(text);
  const tests = files.includes(f.replace('.clas.abap', '.clas.testclasses.abap'));
  if (name.length > 30) problems.push(`${name}: class name longer than 30`);
  const lines = [`    <CLSNAME>${name}</CLSNAME>`, '    <LANGU>E</LANGU>', `    <DESCRIPT>${esc(descr)}</DESCRIPT>`];
  if (forBehavior) lines.push('    <CATEGORY>06</CATEGORY>');
  if (isException) lines.push('    <CATEGORY>40</CATEGORY>');
  lines.push('    <STATE>1</STATE>', '    <CLSCCINCL>X</CLSCCINCL>', '    <FIXPT>X</FIXPT>', '    <UNICODE>X</UNICODE>');
  if (tests) lines.push('    <WITH_UNIT_TESTS>X</WITH_UNIT_TESTS>');
  if (forBehavior) lines.push(`    <CLSDEFINT>${forBehavior[1].toUpperCase()}</CLSDEFINT>`);
  write(f.replace('.abap', '.xml'), wrap('LCL_OBJECT_CLAS', `   <VSEOCLASS>\n${lines.join('\n')}\n   </VSEOCLASS>`));
}

// ---- programs (PROG) with their text pools -------------------------------
const tpool = {
  ZABR_BOLT_SYNC: [
    ['R', '', 'Bolt - send pending migrations to GitHub, read statuses'],
    ['S', 'CB_PUSH', 'Send pending/failed to GitHub'],
    ['S', 'CB_STAT', 'Read statuses from GitHub'],
    ['S', 'P_MAX', 'Maximum send attempts'],
  ],
  ZABR_BOLT_DRIVER_INDEX: [
    ['R', '', 'Bolt - build the Smart Form driver index'],
    ['S', 'P_PREF1', 'First Smart Form prefix'],
    ['S', 'P_PREF2', 'Second Smart Form prefix'],
    ['S', 'CB_TEST', 'Test run (nothing saved)'],
  ],
  ZABR_BOLT_SELFTEST: [
    ['R', '', 'Bolt - backend self-test (export, GitHub, AI)'],
    ['S', 'P_FORM', 'Smart Form'],
    ['S', 'CB_DOWN', 'Download the files to the PC'],
    ['S', 'P_PATH', 'PC folder'],
    ['S', 'CB_GH', 'Check the GitHub connection'],
    ['S', 'CB_AI', 'Check the AI provider'],
  ],
};
for (const f of files.filter((x) => x.endsWith('.prog.abap'))) {
  const name = f.replace('.prog.abap', '').toUpperCase();
  const items = (tpool[name] || []).map(([id, key, entry]) => {
    if (id === 'S' && entry.length > 30) problems.push(`${name} ${key}: selection text longer than 30`);
    return `    <item>
     <ID>${id}</ID>${key ? `\n     <KEY>${key}</KEY>` : ''}
     <ENTRY>${esc(entry)}</ENTRY>
     <LENGTH>${Math.min(entry.length + 10, id === 'R' ? 70 : id === 'S' ? 30 : 132)}</LENGTH>
    </item>`;
  });
  write(f.replace('.abap', '.xml'), wrap('LCL_OBJECT_PROG', `   <PROGDIR>
    <NAME>${name}</NAME>
    <DBAPL>S</DBAPL>
    <SUBC>1</SUBC>
    <APPL>X</APPL>
    <FIXPT>X</FIXPT>
    <UCCHECK>X</UCCHECK>
   </PROGDIR>
   <TPOOL>
${items.join('\n')}
   </TPOOL>`));
}

// ---- service definition, binding and its gateway registration -----------
const SRVD = 'ZAB_UI_BOLT';
const SRVB = 'ZAB_UI_BOLT_O4';
write(`${SRVD.toLowerCase()}.srvd.xml`, wrap('LCL_OBJECT_SRVD', `   <SRVD>
    <NAME>${SRVD}</NAME>
    <TYPE>SRVD/SRV</TYPE>
    <DESCRIPTION>Bolt - Smart Form migration (Fiori UI)</DESCRIPTION>
    <LANGUAGE>EN</LANGUAGE>
    <MASTER_LANGUAGE>EN</MASTER_LANGUAGE>
    <SOURCE_URI>./${SRVD.toLowerCase()}/source/main</SOURCE_URI>
    <SOURCE_TYPE>ABAP_SOURCE</SOURCE_TYPE>
    <SOURCE_ORIGIN_DESCRIPTION>ABAP Development Tools</SOURCE_ORIGIN_DESCRIPTION>
    <SRVD_SOURCE_TYPE>S</SRVD_SOURCE_TYPE>
    <SRVD_SOURCE_TYPE_DESC>Definition</SRVD_SOURCE_TYPE_DESC>
   </SRVD>`));
write(`${SRVB.toLowerCase()}.srvb.xml`, wrap('LCL_OBJECT_SRVB', `   <SRVB>
    <METADATA>
     <NAME>${SRVB}</NAME>
     <TYPE>SRVB/SVB</TYPE>
     <DESCRIPTION>Bolt - UI service binding (OData V4)</DESCRIPTION>
    </METADATA>
    <CONTENT>
     <BIND_TYPE_IMPL>
      <NAME>${SRVB}</NAME>
     </BIND_TYPE_IMPL>
     <BIND_TYPE>ODATA</BIND_TYPE>
     <BIND_TYPE_VERSION>V4</BIND_TYPE_VERSION>
     <SERVICES>
      <item>
       <SERVICE_NAME>${SRVD}</SERVICE_NAME>
       <SERVICE_CONTENT>
        <item>
         <SERVICE_VERSION>0001</SERVICE_VERSION>
         <RELEASE_STATE>NOT_RELEASED</RELEASE_STATE>
         <SRVD_REF>
          <URI>/sap/bc/adt/ddic/srvd/sources/${SRVD.toLowerCase()}</URI>
          <TYPE>SRVD/SRV</TYPE>
          <NAME>${SRVD}</NAME>
         </SRVD_REF>
         <BIND_TYPE_DATA>
          <CONTENT>
           <ENCODING>base64</ENCODING>
          </CONTENT>
         </BIND_TYPE_DATA>
        </item>
       </SERVICE_CONTENT>
      </item>
     </SERVICES>
    </CONTENT>
    <CONTRACT>C1</CONTRACT>
    <RELEASE_SUPPORTED>true</RELEASE_SUPPORTED>
    <PUBLISHED>true</PUBLISHED>
    <BINDING_CREATED>true</BINDING_CREATED>
   </SRVB>`));
write(`${SRVB.toLowerCase()}.g4ba.xml`, wrap('LCL_OBJECT_G4BA', `   <_-IWBEP_-I_V4_MSGA>
    <_-IWBEP_-I_V4_MSGA>
     <GROUP_ID>${SRVB}</GROUP_ID>
     <SERVICE_ID>/IWBEP/COMMON</SERVICE_ID>
     <REPOSITORY_ID>DEFAULT</REPOSITORY_ID>
     <GWBEP_VERSION>031</GWBEP_VERSION>
    </_-IWBEP_-I_V4_MSGA>
   </_-IWBEP_-I_V4_MSGA>
   <_-IWBEP_-I_V4_MSGR>
    <_-IWBEP_-I_V4_MSGR>
     <GROUP_ID>${SRVB}</GROUP_ID>
     <GWBEP_VERSION>031</GWBEP_VERSION>
     <ASSIGNMENT_REPO_ID>SADL</ASSIGNMENT_REPO_ID>
     <EXTERNAL_GROUP_ID>${SRVB}</EXTERNAL_GROUP_ID>
    </_-IWBEP_-I_V4_MSGR>
   </_-IWBEP_-I_V4_MSGR>
   <_-IWBEP_-I_V4_MSGT>
    <_-IWBEP_-I_V4_MSGT>
     <GROUP_ID>${SRVB}</GROUP_ID>
     <LANGUAGE>E</LANGUAGE>
     <DESCRIPTION>Bolt - UI service binding</DESCRIPTION>
    </_-IWBEP_-I_V4_MSGT>
   </_-IWBEP_-I_V4_MSGT>`));

// ---- package (the name itself is chosen when linking the repository in abapGit)
write('package.devc.xml', wrap('LCL_OBJECT_DEVC', `   <DEVC>
    <CTEXT>Bolt - Smart Form to Adobe migration console (Fiori)</CTEXT>
   </DEVC>`));

// ---- DIL naming policy (docs/06_naming.md) ----------------------------------
const dil = [
  [/.doma.xml$/, /^zab_dm_bolt_[a-z0-9_]+$/, 30, 'domain ZAB_DM_BOLT_*'],
  [/.dtel.xml$/, /^zab_de_bolt_[a-z0-9_]+$/, 30, 'data element ZAB_DE_BOLT_*'],
  [/.tabl.xml$/, /^zabt_bolt_[a-z0-9_]+$/, 16, 'table ZABT_BOLT_*'],
  [/.ddls.asddls$/, /^zab_cds_(i|c|ce|a)_bolt_[a-z0-9_]+$/, 30, 'CDS ZAB_CDS_<I|C|CE|A>_BOLT_*'],
  [/.prog.abap$/, /^zabr_bolt_[a-z0-9_]+$/, 40, 'report ZABR_BOLT_*'],
  [/.clas.abap$/, /^(zcl_ab_bolt_|zcx_ab_bolt|zbp_ab_bolt_)[a-z0-9_]*$/, 30, 'class ZCL_AB_BOLT_* / ZCX_AB_BOLT / ZBP_AB_BOLT_*'],
];
for (const f of fs.readdirSync(src)) {
  for (const [ext, re, max, what] of dil) {
    if (!ext.test(f)) continue;
    const n = f.replace(ext, '');
    if (!re.test(n)) problems.push(`${f}: name must follow the DIL pattern ${what}`);
    if (n.length > max) problems.push(`${f}: name longer than ${max}`);
  }
}

// ---- every metadata .xml (incl. package, tables) carries the BOM --------------
for (const f of fs.readdirSync(src).filter((x) => x.endsWith('.xml'))) {
  const t = read(f);
  if (t.charCodeAt(0) !== 0xfeff) { write(f, BOM + t); console.log(`added BOM to ${f}`); }
}
const abapgit = path.join(root, '.abapgit.xml');
const at = fs.readFileSync(abapgit, 'utf8');
if (at.charCodeAt(0) !== 0xfeff) fs.writeFileSync(abapgit, BOM + at, 'utf8');

// ---- completeness: every source has its metadata and vice versa ----------
const all = fs.readdirSync(src);
for (const f of all) {
  if (f.endsWith('.clas.abap') && !all.includes(f.replace('.abap', '.xml'))) problems.push(`${f}: no .clas.xml`);
  if (f.endsWith('.clas.xml') && !all.includes(f.replace('.xml', '.abap'))) problems.push(`${f}: no .clas.abap`);
  if (f.endsWith('.ddls.asddls') && !all.includes(f.replace('.asddls', '.baseinfo'))) problems.push(`${f}: no baseinfo`);
}
for (const t of all.filter((x) => x.endsWith('.tabl.xml'))) {
  const n = t.replace('.tabl.xml', '');
  if (n.length > 16) problems.push(`${n}: table name longer than 16`);
}

console.log(`${all.length} files in src/`);
if (problems.length) {
  console.error('PROBLEMS:\n' + problems.join('\n'));
  process.exit(1);
}
console.log('metadata OK');
