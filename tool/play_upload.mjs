#!/usr/bin/env node
/**
 * Google Play uploads for AyahReel through the Play Developer API, run by
 * .github/workflows/play-upload.yml. Keyless: the workflow trades its GitHub
 * OIDC token for a 1-hour Play token (play-api service account).
 *
 *   PLAY_TOKEN=<token> node tool/play_upload.mjs check
 *   PLAY_TOKEN=<token> PLAY_AAB=<file> node tool/play_upload.mjs upload
 *
 * check   print every track's releases and the bundle library; changes nothing
 * upload  add PLAY_AAB to production as a DRAFT release, carrying the notes
 *         of the newest production release that has some. A draft reaches
 *         no one: it waits for "Send for review" in Play Console.
 *
 * Everything goes into one edit, committed at the end, so a failure changes
 * nothing. Modelled on Mulhimfy/freed's scripts/play.mjs.
 */
import { readFileSync, existsSync, statSync } from 'node:fs';

const PKG = 'com.ayahreel.app';
const TRACK = 'production';
const TOKEN = process.env.PLAY_TOKEN;
const AAB = process.env.PLAY_AAB;
const action = process.argv[2] ?? 'check';

const API = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PKG}`;
const UPLOAD = `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${PKG}`;

function fail(msg) {
  console.error(`::error::${msg}`);
  process.exit(1);
}

if (!TOKEN) fail('PLAY_TOKEN is not set');
if (!['check', 'upload'].includes(action)) fail(`unknown action "${action}"`);

async function call(method, url, { body, type = 'application/json' } = {}) {
  const res = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${TOKEN}`, ...(body !== undefined ? { 'Content-Type': type } : {}) },
    body: body === undefined ? undefined : type === 'application/json' ? JSON.stringify(body) : body,
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : {};
  if (!res.ok) {
    const msg = data.error?.message ?? text;
    const err = new Error(`${method} ${url.replace(/^https:\/\/[^/]+/, '')} → ${res.status}: ${msg}`);
    err.apiMessage = msg;
    throw err;
  }
  return data;
}

const topCode = (r) => Math.max(0, ...(r.versionCodes ?? []).map(Number));
const describe = (r) =>
  `${r.name ?? '?'} [${(r.versionCodes ?? []).join(',')}] ${r.status}${r.userFraction ? ` ${r.userFraction * 100}%` : ''}`;

async function commit(edit) {
  try {
    await call('POST', `${API}/edits/${edit}:commit`);
  } catch (e) {
    if (!/changesNotSentForReview/i.test(e.apiMessage ?? '')) throw e;
    await call('POST', `${API}/edits/${edit}:commit?changesNotSentForReview=true`);
  }
}

const { id: edit } = await call('POST', `${API}/edits`).catch((e) =>
  fail(/permission/i.test(e.message)
    ? `${e.message}\nThe play-api service account has no access to AyahReel: Play Console → Users and permissions → play-api → app permissions.`
    : e.message));

try {
  if (action === 'check') {
    const { tracks = [] } = await call('GET', `${API}/edits/${edit}/tracks`);
    console.log(`connected to ${PKG}`);
    for (const t of tracks) console.log(`  ${t.track}: ${(t.releases ?? []).map(describe).join(' · ') || 'no releases'}`);
    // Every bundle ever uploaded, released or not: an uploaded version code
    // is spent even if its draft was discarded ("already been used").
    const { bundles = [] } = await call('GET', `${API}/edits/${edit}/bundles`);
    const codes = bundles.map((b) => Number(b.versionCode)).sort((a, b) => a - b);
    console.log(`  bundle library: ${codes.join(', ') || 'empty'}`);
    await call('DELETE', `${API}/edits/${edit}`);
  } else {
    if (!AAB || !existsSync(AAB)) fail(`no bundle at PLAY_AAB=${AAB}`);
    const { releases = [] } = await call('GET', `${API}/edits/${edit}/tracks/${TRACK}`);
    const notesFrom = releases.filter((r) => r.releaseNotes?.length).sort((a, b) => topCode(b) - topCode(a))[0];

    console.log(`uploading ${AAB} (${(statSync(AAB).size / 1e6).toFixed(1)} MB)`);
    const { versionCode } = await call('POST', `${UPLOAD}/edits/${edit}/bundles?uploadType=media`, {
      body: readFileSync(AAB),
      type: 'application/octet-stream',
    });

    // A track holds one draft at most: the new one replaces any other.
    const replaced = releases.filter((r) => r.status === 'draft');
    for (const r of replaced) console.log(`replacing the earlier draft ${describe(r)}`);
    const draft = { versionCodes: [String(versionCode)], status: 'draft', ...(notesFrom ? { releaseNotes: notesFrom.releaseNotes } : {}) };
    await call('PUT', `${API}/edits/${edit}/tracks/${TRACK}`, {
      body: { track: TRACK, releases: [...releases.filter((r) => r.status !== 'draft'), draft] },
    });
    await commit(edit);

    const notes = notesFrom
      ? `release notes in ${notesFrom.releaseNotes.length} languages copied from ${notesFrom.name ?? topCode(notesFrom)}`
      : 'no release notes (none on the track to copy)';
    console.log(`versionCode ${versionCode} is now a DRAFT on ${TRACK}, ${notes}.`);
    console.log('It reaches no one until "Send for review" / rollout in Play Console.');
  }
} catch (e) {
  await call('DELETE', `${API}/edits/${edit}`).catch(() => {});
  fail(e.message);
}
