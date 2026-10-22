#!/usr/bin/env node
/**
 * Google Play uploads for AyahReel through the Play Developer API, run by
 * .github/workflows/play-upload.yml and android-release.yml. Keyless: the
 * workflow trades its GitHub OIDC token for a 1-hour Play token (play-api
 * service account).
 *
 *   PLAY_TOKEN=<token> node tool/play_upload.mjs check
 *   PLAY_TOKEN=<token> PLAY_AAB=<file> node tool/play_upload.mjs upload
 *   PLAY_TOKEN=<token> PLAY_AAB=<file> PLAY_NOTES=<json> node tool/play_upload.mjs release
 *
 * check    print every track's releases, the newest production release's
 *          notes and the bundle library; changes nothing
 * upload   add PLAY_AAB to production as a DRAFT release, carrying the notes
 *          of the newest production release that has some. A draft reaches
 *          no one: it waits for "Send for review" in Play Console.
 * release  add PLAY_AAB to production for everyone (status completed), with
 *          the notes in PLAY_NOTES ({"en-US": "…", "ar": "…"}). The commit
 *          sends it for review, and Play gives it to every user once it
 *          passes. This ships. PLAY_VERSION_CODE names the bundle when a
 *          rerun finds it uploaded already.
 *
 * Everything goes into one edit, committed at the end, so a failure changes
 * nothing. Modelled on Mulhimfy/freed's scripts/play.mjs.
 */
import { readFileSync, existsSync, statSync } from 'node:fs';

const PKG = 'com.ayahreel.app';
const TRACK = 'production';
const TOKEN = process.env.PLAY_TOKEN;
const AAB = process.env.PLAY_AAB;
const NOTES = process.env.PLAY_NOTES;
const action = process.argv[2] ?? 'check';

const API = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${PKG}`;
const UPLOAD = `https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/${PKG}`;

function fail(msg) {
  console.error(`::error::${msg}`);
  process.exit(1);
}

if (!TOKEN) fail('PLAY_TOKEN is not set');
if (!['check', 'upload', 'release'].includes(action)) fail(`unknown action "${action}"`);

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

// Returns whether the changes went to review. Play refuses the plain commit
// when they can't be sent automatically; they are then saved, and wait for
// "Send for review" in Play Console.
async function commit(edit) {
  try {
    await call('POST', `${API}/edits/${edit}:commit`);
    return true;
  } catch (e) {
    if (!/changesNotSentForReview/i.test(e.apiMessage ?? '')) throw e;
    await call('POST', `${API}/edits/${edit}:commit?changesNotSentForReview=true`);
    return false;
  }
}

// The bundle's version code. A rerun of a release whose upload went through
// finds the code spent ("already been used"): the bundle is in the library,
// so it is released from there.
async function uploadBundle(edit) {
  if (!AAB || !existsSync(AAB)) fail(`no bundle at PLAY_AAB=${AAB}`);
  console.log(`uploading ${AAB} (${(statSync(AAB).size / 1e6).toFixed(1)} MB)`);
  try {
    const { versionCode } = await call('POST', `${UPLOAD}/edits/${edit}/bundles?uploadType=media`, {
      body: readFileSync(AAB),
      type: 'application/octet-stream',
    });
    return String(versionCode);
  } catch (e) {
    const code = process.env.PLAY_VERSION_CODE;
    if (!code || !/already been used/i.test(e.apiMessage ?? '')) throw e;
    const { bundles = [] } = await call('GET', `${API}/edits/${edit}/bundles`);
    if (!bundles.some((b) => String(b.versionCode) === code)) throw e;
    console.log(`versionCode ${code} was uploaded before; releasing it from the bundle library`);
    return code;
  }
}

// {"en-US": "…"} → Play's releaseNotes. Play takes 500 characters a language.
function readNotes() {
  if (!NOTES || !existsSync(NOTES)) fail(`no release notes at PLAY_NOTES=${NOTES}`);
  const notes = JSON.parse(readFileSync(NOTES, 'utf8'));
  const list = Object.entries(notes).map(([language, text]) => ({ language, text: String(text).trim() }));
  if (!list.length) fail(`${NOTES} has no notes`);
  for (const n of list) {
    if (!n.text) fail(`${NOTES}: the ${n.language} notes are empty`);
    if ([...n.text].length > 500) fail(`${NOTES}: the ${n.language} notes are ${[...n.text].length} characters; Play takes 500`);
  }
  return list;
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
    const newest = (tracks.find((t) => t.track === TRACK)?.releases ?? [])
      .filter((r) => r.releaseNotes?.length)
      .sort((a, b) => topCode(b) - topCode(a))[0];
    if (newest) {
      console.log(`  notes of ${newest.name ?? topCode(newest)}:`);
      for (const n of newest.releaseNotes) console.log(`    ${n.language}: ${n.text.replace(/\n/g, ' / ')}`);
    }
    // Every bundle ever uploaded, released or not: an uploaded version code
    // is spent even if its draft was discarded ("already been used").
    const { bundles = [] } = await call('GET', `${API}/edits/${edit}/bundles`);
    const codes = bundles.map((b) => Number(b.versionCode)).sort((a, b) => a - b);
    console.log(`  bundle library: ${codes.join(', ') || 'empty'}`);
    await call('DELETE', `${API}/edits/${edit}`);
  } else if (action === 'upload') {
    const { releases = [] } = await call('GET', `${API}/edits/${edit}/tracks/${TRACK}`);
    const notesFrom = releases.filter((r) => r.releaseNotes?.length).sort((a, b) => topCode(b) - topCode(a))[0];

    const versionCode = await uploadBundle(edit);

    // A track holds one draft at most: the new one replaces any other.
    const replaced = releases.filter((r) => r.status === 'draft');
    for (const r of replaced) console.log(`replacing the earlier draft ${describe(r)}`);
    const draft = { versionCodes: [versionCode], status: 'draft', ...(notesFrom ? { releaseNotes: notesFrom.releaseNotes } : {}) };
    await call('PUT', `${API}/edits/${edit}/tracks/${TRACK}`, {
      body: { track: TRACK, releases: [...releases.filter((r) => r.status !== 'draft'), draft] },
    });
    await commit(edit);

    const notes = notesFrom
      ? `release notes in ${notesFrom.releaseNotes.length} languages copied from ${notesFrom.name ?? topCode(notesFrom)}`
      : 'no release notes (none on the track to copy)';
    console.log(`versionCode ${versionCode} is now a DRAFT on ${TRACK}, ${notes}.`);
    console.log('It reaches no one until "Send for review" / rollout in Play Console.');
  } else {
    const releaseNotes = readNotes();
    const { releases = [] } = await call('GET', `${API}/edits/${edit}/tracks/${TRACK}`);
    for (const r of releases) console.log(`on ${TRACK} before: ${describe(r)}`);

    const versionCode = await uploadBundle(edit);
    const live = Math.max(0, ...releases.filter((r) => r.status === 'completed').map(topCode));
    if (Number(versionCode) <= live) fail(`versionCode ${versionCode} is not above ${live}, which ${TRACK} already gives everyone`);

    // One completed release: it takes over from the one before it, for
    // every user, and any draft goes with it.
    const release = { versionCodes: [versionCode], status: 'completed', releaseNotes };
    await call('PUT', `${API}/edits/${edit}/tracks/${TRACK}`, {
      body: { track: TRACK, releases: [release] },
    });
    const { releases: after = [] } = await call('GET', `${API}/edits/${edit}/tracks/${TRACK}`);
    for (const r of after) console.log(`on ${TRACK} after: ${describe(r)}`);
    const sent = await commit(edit);

    console.log(`versionCode ${versionCode} is on ${TRACK} for everyone, notes in ${releaseNotes.map((n) => n.language).join(', ')}.`);
    if (sent) {
      console.log('Sent for review: Play gives it to every user once it passes.');
    } else {
      console.log('::warning::Saved, but Play did not send it for review by itself: Play Console → Publishing overview → "Send changes for review".');
    }
  }
} catch (e) {
  await call('DELETE', `${API}/edits/${edit}`).catch(() => {});
  fail(e.message);
}
