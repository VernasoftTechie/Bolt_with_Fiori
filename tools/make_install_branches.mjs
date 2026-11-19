// Builds the four abapGit install branches from the current commit of main:
//
//   install/1-ddic     domains, data elements, tables (+ package)
//   install/2-logic    + exception, service classes, driver-index and self-test reports
//   install/3-rap      + CDS views, behaviours, query classes, sync report
//   install/4-service  + service definition and binding  (= everything on main)
//
// Each branch is cumulative: link abapGit to install/1-ddic, pull, activate,
// then switch the abapGit repository to the next branch and pull again
// (docs/04_installation.md). Everything outside src/ (docs, app, tools) is kept
// on every branch, so the guide is always next to the objects.
//
//   node tools/make_install_branches.mjs          (after committing on main)
//   git push origin main "install/*"              (or: git push --all origin)
//
// Uses git plumbing with a private index - the working tree and the normal
// index are never touched.
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const indexFile = path.join(os.tmpdir(), `bolt-install-index-${process.pid}`);
const git = (args, extraEnv = {}) =>
  execFileSync('git', args, { cwd: root, encoding: 'utf8', env: { ...process.env, ...extraEnv } }).trim();

// Which increment an object under src/ belongs to.
export function incrementOf(file) {
  const f = path.basename(file);
  if (f === 'package.devc.xml' || /\.(doma|dtel|tabl)\.xml$/.test(f)) return 1;
  if (/\.(srvd|srvb|g4ba)\./.test(f)) return 4;
  if (/\.(ddls|bdef)\./.test(f) || /^zbp_ab_bolt_/.test(f) || /^zcl_ab_bolt_q_/.test(f) || /^zabr_bolt_sync\./.test(f)) return 3;
  if (/^(zcx_ab_bolt|zcl_ab_bolt_|zabr_bolt_)/.test(f)) return 2;
  throw new Error(`No increment rule for ${file} - add one in tools/make_install_branches.mjs`);
}

const branches = [
  [1, 'install/1-ddic', 'Install increment 1: DDIC (domains, data elements, tables)'],
  [2, 'install/2-logic', 'Install increment 2: service classes and reports'],
  [3, 'install/3-rap', 'Install increment 3: CDS views and RAP business objects'],
  [4, 'install/4-service', 'Install increment 4: OData V4 service definition and binding'],
];

if (process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1])) {
  const head = git(['rev-parse', 'HEAD']);
  const all = git(['ls-tree', '-r', '--name-only', 'HEAD']).split('\n').filter(Boolean);
  const src = all.filter((f) => f.startsWith('src/'));
  const counts = {};
  for (const f of src) {
    const n = incrementOf(f);
    counts[n] = (counts[n] || 0) + 1;
  }
  try {
    for (const [n, branch, message] of branches) {
      const env = { GIT_INDEX_FILE: indexFile };
      git(['read-tree', head], env);
      const drop = src.filter((f) => incrementOf(f) > n);
      for (let i = 0; i < drop.length; i += 200) git(['rm', '--cached', '--quiet', '--', ...drop.slice(i, i + 200)], env);
      const tree = git(['write-tree'], env);
      let parent = '';
      try { parent = git(['rev-parse', '--verify', '--quiet', `refs/heads/${branch}`]); } catch { parent = ''; }
      if (parent && git(['rev-parse', `${parent}^{tree}`]) === tree) {
        console.log(`${branch}: unchanged (${src.length - drop.length} objects files)`);
        continue;
      }
      const args = ['commit-tree', tree, '-m', `${message}\n\nBuilt from main ${head.slice(0, 7)} by tools/make_install_branches.mjs.`];
      if (parent) args.push('-p', parent);
      args.push('-p', head);
      const commit = git(args);
      git(['update-ref', `refs/heads/${branch}`, commit]);
      console.log(`${branch}: ${commit.slice(0, 7)} (${src.length - drop.length} files in src/)`);
    }
  } finally {
    fs.rmSync(indexFile, { force: true });
  }
  console.log(`objects per increment (files): ${JSON.stringify(counts)}`);
}
