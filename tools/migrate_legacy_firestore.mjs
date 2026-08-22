#!/usr/bin/env node

/*
 * One-time Firestore Admin migration.
 *
 * This tool is deliberately dry-run by default. It never guesses an owner for
 * a legacy root business document, because the old schema did not save owner
 * UIDs. Supply either --owner-uid for a known single-tenant legacy database or
 * --ownership-file for a per-document mapping before --apply is permitted.
 */

import fs from 'node:fs/promises';
import process from 'node:process';
import {applicationDefault, initializeApp} from 'firebase-admin/app';
import {FieldValue, getFirestore} from 'firebase-admin/firestore';
import {getAuth} from 'firebase-admin/auth';

const businessCollections = [
  'products',
  'customers',
  'categories',
  'sales',
  'draft_products',
];

function parseArguments(argv) {
  const options = {
    apply: false,
    deleteLegacy: false,
    ownerUid: null,
    ownershipFile: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    switch (argv[index]) {
      case '--apply':
        options.apply = true;
        break;
      case '--delete-legacy':
        options.deleteLegacy = true;
        break;
      case '--owner-uid':
        options.ownerUid = argv[++index] ?? null;
        break;
      case '--ownership-file':
        options.ownershipFile = argv[++index] ?? null;
        break;
      case '--help':
        console.log(`Usage:
  node tools/migrate_legacy_firestore.mjs [--apply]
      [--owner-uid AUTH_UID | --ownership-file tools/ownership.json]
      [--delete-legacy]

Default is a dry run. --delete-legacy requires --apply and only removes a
legacy document after its user-scoped copy has been confirmed.`);
        process.exit(0);
      default:
        throw new Error(`Unknown argument: ${argv[index]}`);
    }
  }
  if (options.deleteLegacy && !options.apply) {
    throw new Error('--delete-legacy requires --apply.');
  }
  return options;
}

function authEmailForUsername(username) {
  const normalized = String(username).trim().toLowerCase();
  if (!/^[a-z0-9_]{3,}$/.test(normalized)) {
    throw new Error(`Legacy username is not valid for Firebase Auth: ${username}`);
  }
  return `${normalized}@smartstore.local`;
}

async function loadOwnership(filePath) {
  if (!filePath) return {};
  const content = await fs.readFile(filePath, 'utf8');
  const data = JSON.parse(content);
  if (data === null || Array.isArray(data) || typeof data !== 'object') {
    throw new Error('The ownership file must be a JSON object.');
  }
  return data;
}

async function ensureLegacyAuthUsers({db, auth, apply}) {
  const users = await db.collection('users').get();
  const usernameToUid = new Map();
  const report = {created: 0, existing: 0, skipped: 0};

  for (const document of users.docs) {
    const data = document.data();
    const username = String(data.username ?? '').trim();
    const password = data.password;
    if (!username || typeof password !== 'string' || password.length < 6) {
      report.skipped += 1;
      console.warn(`SKIP user ${document.id}: username or legacy password is invalid.`);
      continue;
    }

    const email = authEmailForUsername(username);
    const normalizedUsername = username.toLowerCase();
    if (usernameToUid.has(normalizedUsername)) {
      throw new Error(`Duplicate legacy username found: ${username}`);
    }
    usernameToUid.set(normalizedUsername, document.id);

    try {
      const existing = await auth.getUserByEmail(email);
      if (existing.uid !== document.id) {
        throw new Error(
          `Auth email ${email} belongs to ${existing.uid}, not legacy user ${document.id}.`,
        );
      }
      report.existing += 1;
    } catch (error) {
      if (error.code !== 'auth/user-not-found') throw error;
      if (apply) {
        await auth.createUser({
          uid: document.id,
          email,
          password,
          displayName: String(data.fullName ?? ''),
        });
        await document.ref.set({
          uid: document.id,
          username,
          usernameLower: normalizedUsername,
          migratedAt: FieldValue.serverTimestamp(),
          password: FieldValue.delete(),
        }, {merge: true});
      }
      report.created += 1;
    }
  }
  return {usernameToUid, report};
}

async function copyDocument({source, target, apply}) {
  if (!apply) return 'planned';
  const targetSnapshot = await target.get();
  if (targetSnapshot.exists) {
    return targetSnapshot.data()?._legacyMigrationSource === source.ref.path
      ? 'already-copied'
      : 'already-present';
  }
  await target.create({
    ...source.data(),
    _legacyMigrationSource: source.ref.path,
    _legacyMigratedAt: FieldValue.serverTimestamp(),
  });
  return 'copied';
}

async function migrateBusinessCollections({
  db,
  apply,
  deleteLegacy,
  ownerUid,
  ownership,
}) {
  const summary = {};
  for (const collectionName of businessCollections) {
    const snapshot = await db.collection(collectionName).get();
    let copied = 0;
    let skipped = 0;
    let deleted = 0;

    for (const document of snapshot.docs) {
      const mappedOwner = ownership[collectionName]?.[document.id];
      const destinationUid = mappedOwner ?? ownerUid;
      if (!destinationUid) {
        skipped += 1;
        console.warn(
          `SKIP ${collectionName}/${document.id}: no explicit owner mapping.`,
        );
        continue;
      }

      const target = db.doc(`users/${destinationUid}/${collectionName}/${document.id}`);
      const status = await copyDocument({source: document, target, apply});
      if (status === 'planned' || status === 'copied' || status === 'already-copied') {
        copied += 1;
      }
      if (deleteLegacy && apply && (status === 'copied' || status === 'already-copied')) {
        await document.ref.delete();
        deleted += 1;
      } else if (deleteLegacy && status === 'already-present') {
        console.warn(
          `NOT DELETED ${collectionName}/${document.id}: destination was not created by this migration.`,
        );
      }
    }
    summary[collectionName] = {total: snapshot.size, copied, skipped, deleted};
  }
  return summary;
}

async function migrateActivityLogs({
  db,
  usernameToUid,
  apply,
  deleteLegacy,
  ownerUid,
}) {
  const snapshot = await db.collection('activity_logs').get();
  let copied = 0;
  let skipped = 0;
  let deleted = 0;
  for (const document of snapshot.docs) {
    const username = String(document.data().username ?? '').trim().toLowerCase();
    const destinationUid = usernameToUid.get(username) ?? ownerUid;
    if (!destinationUid) {
      skipped += 1;
      console.warn(`SKIP activity_logs/${document.id}: unknown owner.`);
      continue;
    }
    const target = db.doc(`users/${destinationUid}/activity_logs/${document.id}`);
    const status = await copyDocument({source: document, target, apply});
    if (status === 'planned' || status === 'copied' || status === 'already-copied') {
      copied += 1;
    }
    if (deleteLegacy && apply && (status === 'copied' || status === 'already-copied')) {
      await document.ref.delete();
      deleted += 1;
    } else if (deleteLegacy && status === 'already-present') {
      console.warn(
        `NOT DELETED activity_logs/${document.id}: destination was not created by this migration.`,
      );
    }
  }
  return {total: snapshot.size, copied, skipped, deleted};
}

async function main() {
  const options = parseArguments(process.argv.slice(2));
  const ownership = await loadOwnership(options.ownershipFile);
  initializeApp({credential: applicationDefault()});
  const db = getFirestore();
  const auth = getAuth();

  console.log(options.apply ? 'APPLY MODE' : 'DRY RUN — no Firebase data will change');
  const {usernameToUid, report: users} = await ensureLegacyAuthUsers({
    db,
    auth,
    apply: options.apply,
  });
  const business = await migrateBusinessCollections({
    db,
    apply: options.apply,
    deleteLegacy: options.deleteLegacy,
    ownerUid: options.ownerUid,
    ownership,
  });
  const activityLogs = await migrateActivityLogs({
    db,
    usernameToUid,
    apply: options.apply,
    deleteLegacy: options.deleteLegacy,
    ownerUid: options.ownerUid,
  });
  console.table({users, activityLogs, ...business});
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
