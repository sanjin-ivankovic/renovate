#!/usr/bin/env node
// Lane report: what Renovate would do with every dependency of a dry run.
//
// Reads a Renovate debug log (LOG_FORMAT=json) from a lookup dry run and
// resolves each dependency x update type through the engine's own
// applyPackageRules, against the repo config the run resolved ("Resolved
// shallow config": the repo's rules plus the local> presets; Renovate's
// built-in presets are not expanded, they set no soak or automerge here).
//
// Columns: repo, package file, dependency, update type, lane label, soak,
// automerge, release date of the current version (ts / no-ts), and the
// effective automerge: an automerge whose soak needs a release date the
// registry does not publish never turns green, so it is effectively manual.
//
// The engine is found next to the `renovate` on PATH (npx or Homebrew), or
// at $RENOVATE_DIST. Run it through `make lanes` / `make lanes-local`, which
// put the engine version CI uses on PATH.
//
// Usage: node scripts/lane-report.mjs <debug-log.ndjson> [repo substring]

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

function engineDist() {
  if (process.env.RENOVATE_DIST) return process.env.RENOVATE_DIST;
  const bin = execFileSync('sh', ['-c', 'command -v renovate'], { encoding: 'utf8' }).trim();
  const real = fs.realpathSync(bin);
  const dir = path.dirname(real);
  const candidates = [
    dir, // npx: node_modules/renovate/dist/renovate.js
    path.join(dir, '..', 'dist'),
    path.join(dir, '..', 'libexec', 'lib', 'node_modules', 'renovate', 'dist'), // Homebrew
    path.join(dir, '..', 'lib', 'node_modules', 'renovate', 'dist'),
  ];
  const found = candidates.find((d) => fs.existsSync(path.join(d, 'util', 'package-rules', 'index.js')));
  if (!found) throw new Error(`renovate engine not found next to ${real}; set RENOVATE_DIST`);
  return found;
}

const [log, only] = process.argv.slice(2);
if (!log) {
  console.error('usage: lane-report.mjs <debug-log.ndjson> [repo substring]');
  process.exit(2);
}

const { applyPackageRules } = await import(path.join(engineDist(), 'util', 'package-rules', 'index.js'));

const entries = fs
  .readFileSync(log, 'utf8')
  .split('\n')
  .filter(Boolean)
  .map((line) => {
    try {
      return JSON.parse(line);
    } catch {
      return null;
    }
  })
  .filter(Boolean);

const configByRepo = {};
const filesByRepo = {};
for (const e of entries) {
  const repo = e.repository ?? 'local';
  if (e.msg === 'Resolved shallow config, without merging internal presets' && e.config) configByRepo[repo] = e.config;
  if (e.msg === 'packageFiles with updates' && e.config) filesByRepo[repo] = e.config;
}
if (!Object.keys(filesByRepo).length) {
  console.error(`no "packageFiles with updates" entry in ${log}: did the dry run fail? (grep '"level":[45]0')`);
  process.exit(1);
}

const rows = [['repo', 'file', 'dependency', 'update', 'lane', 'soak', 'automerge', 'release-date', 'effective']];
for (const [repo, managers] of Object.entries(filesByRepo)) {
  if (only && !repo.includes(only)) continue;
  const base = configByRepo[repo] ?? {};
  for (const [manager, files] of Object.entries(managers)) {
    for (const file of files) {
      for (const dep of file.deps) {
        for (const updateType of ['patch', 'minor', 'major', 'digest']) {
          const c = await applyPackageRules(
            { ...base, ...dep, manager, packageFile: file.packageFile, updateType, isBump: false },
            'update-type',
          );
          if (c.enabled === false) continue;
          const lane = (c.addLabels ?? []).find((l) => l.startsWith('lane::')) ?? '-';
          const dated = Boolean(dep.currentVersionTimestamp);
          const effective =
            c.automerge && (dated || !c.minimumReleaseAge || c.minimumReleaseAgeBehaviour === 'timestamp-optional');
          rows.push([
            repo.replace(/^homelab\//, ''),
            file.packageFile,
            dep.packageName ?? dep.depName ?? '-',
            updateType,
            lane,
            c.minimumReleaseAge ?? 'none',
            c.automerge ? 'auto' : 'manual',
            dated ? 'ts' : 'no-ts',
            effective ? 'auto' : 'manual',
          ]);
        }
      }
    }
  }
}
console.log(rows.map((r) => r.join('\t')).join('\n'));
