import { after, before, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs,
  serverTimestamp, setDoc, updateDoc,
} from 'firebase/firestore';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
let env;
const verified = uid => env.authenticatedContext(uid, {email_verified: true}).firestore();
const unverified = uid => env.authenticatedContext(uid, {email_verified: false}).firestore();

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-fmate-spark',
    firestore: {
      host: '127.0.0.1',
      port: 8085,
      rules: readFileSync(resolve(root, 'firestore.rules'), 'utf8'),
    },
  });
});

after(async () => { await env?.cleanup(); });

// Every test runs against Firestore emulator security rules, never production.
test('private data denies unauthenticated access and cross-user reads', async () => {
  const alice = verified('alice');
  const anon = env.unauthenticatedContext().firestore();
  await assertSucceeds(setDoc(doc(alice, 'private_users/alice'), {
    consents: {AGE_14: true, TERMS: true, PRIVACY: true},
    createdAt: serverTimestamp(),
  }));
  await assertSucceeds(getDoc(doc(alice, 'private_users/alice')));
  await assertFails(getDoc(doc(anon, 'private_users/alice')));
  await assertFails(getDoc(doc(verified('bob'), 'private_users/alice')));
  await assertFails(getDocs(collection(alice, 'private_users')));
});

test('profiles require owner and reject arbitrary additional fields', async () => {
  const alice = verified('alice');
  await assertSucceeds(setDoc(doc(alice, 'profiles/alice'), {
    nickname: '앨리스', createdAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(verified('bob'), 'profiles/alice'), {
    nickname: 'evil', createdAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(verified('carol'), 'profiles/carol'), {
    nickname: '캐롤', isAdmin: true, createdAt: serverTimestamp(),
  }));
});

test('posts require verified author and authentic nickname', async () => {
  const post = {authorUid:'alice', authorName:'앨리스', body:'안녕하세요', createdAt:serverTimestamp()};
  await assertFails(setDoc(doc(unverified('alice'), 'demo_posts/p0'), post));
  await assertFails(setDoc(doc(verified('bob'), 'demo_posts/p1'), post));
  await assertSucceeds(setDoc(doc(verified('alice'), 'demo_posts/p2'), post));
  await assertSucceeds(getDoc(doc(env.unauthenticatedContext().firestore(), 'demo_posts/p2')));
  await assertFails(deleteDoc(doc(verified('bob'), 'demo_posts/p2')));
});

test('booking collision is protected and owner alone may cancel', async () => {
  const slot = doc(verified('alice'), 'demo_slots/demo-01_20991231_18');
  await assertSucceeds(setDoc(slot, {
    ownerUid:'alice', venueId:'demo-01', dateKey:'20991231',hour:18,createdAt:serverTimestamp(),
  }));
  await assertFails(setDoc(doc(verified('bob'), 'demo_slots/demo-01_20991231_18'), {
    ownerUid:'bob', venueId:'demo-01', dateKey:'20991231',hour:18,createdAt:serverTimestamp(),
  }));
  await assertFails(deleteDoc(doc(verified('bob'), 'demo_slots/demo-01_20991231_18')));
  await assertSucceeds(deleteDoc(slot));
});

test('chats isolate 1:1 members', async () => {
  await assertSucceeds(setDoc(doc(verified('bob'), 'profiles/bob'), {
    nickname:'밥친구',createdAt:serverTimestamp(),
  }));
  await assertSucceeds(setDoc(doc(verified('alice'), 'demo_chats/alice_bob'), {
    members:['alice','bob'],createdAt:serverTimestamp(),
  }));
  await assertSucceeds(setDoc(doc(verified('bob'), 'demo_chats/alice_bob/messages/m1'), {
    authorUid:'bob',text:'반가워요',sentAt:serverTimestamp(),
  }));
  await assertSucceeds(getDoc(doc(verified('alice'), 'demo_chats/alice_bob/messages/m1')));
  await assertFails(getDoc(doc(verified('carol'), 'demo_chats/alice_bob/messages/m1')));
  await assertFails(setDoc(doc(verified('carol'), 'demo_chats/alice_bob/messages/m2'), {
    authorUid:'carol',text:'침입',sentAt:serverTimestamp(),
  }));
});

test('all other collections stay closed', async () => {
  await assertFails(setDoc(doc(verified('alice'), 'payments/not-real'), {status:'paid'}));
  assert.ok(true);
});


test('private exhibition reservation records allow owner only', async () => {
  const alice = verified('alice');
  const bob = verified('bob');
  const path = 'private_users/alice/demo_reservations/booking-12345';
  await assertSucceeds(setDoc(doc(alice, path), {
    ownerUid: 'alice', venueId: 101, courtId: 1011,
    startsAt: new Date('2099-12-31T09:00:00Z'),
    endsAt: new Date('2099-12-31T10:00:00Z'),
    totalAmount: 45000, status: 'PENDING_PAYMENT',
    createdAt: serverTimestamp(),
  }));
  await assertSucceeds(getDoc(doc(alice, path)));
  await assertFails(getDoc(doc(bob, path)));
  await assertFails(setDoc(doc(bob, 'private_users/alice/demo_reservations/booking-evil'), {
    ownerUid: 'alice', venueId: 101, courtId: 1011,
    startsAt: new Date('2099-12-31T09:00:00Z'),
    endsAt: new Date('2099-12-31T10:00:00Z'),
    totalAmount: 45000, status: 'PENDING_PAYMENT',
    createdAt: serverTimestamp(),
  }));
  await assertFails(deleteDoc(doc(alice, path)));
});


test('likes, comments, and saved posts use member-scoped rules', async () => {
  const alice = verified('alice');
  const bob = verified('bob');
  await assertSucceeds(setDoc(doc(alice, 'demo_posts/p2/likes/alice'), {
    createdAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(bob, 'demo_posts/p2/likes/alice'), {
    createdAt: serverTimestamp(),
  }));
  await assertSucceeds(setDoc(doc(alice, 'demo_posts/p2/comments/c1'), {
    authorUid: 'alice', authorName: '앨리스', body: '좋아요', parentId: null,
    createdAt: serverTimestamp(),
  }));
  await assertFails(setDoc(doc(bob, 'demo_posts/p2/comments/c2'), {
    authorUid: 'alice', authorName: '앨리스', body: '위조 댓글', parentId: null,
    createdAt: serverTimestamp(),
  }));
  await assertSucceeds(setDoc(doc(alice, 'private_users/alice/saved_posts/p2'), {
    createdAt: serverTimestamp(),
  }));
  await assertFails(getDoc(doc(bob, 'private_users/alice/saved_posts/p2')));
});


test('profile editing is limited to the owner and safe public fields', async () => {
  const alice = verified('alice');
  await assertSucceeds(updateDoc(doc(alice, 'profiles/alice'), {
    nickname: '앨리스', bio: '풋살 좋아요', regionCode: '11', preferredPosition: 'ALA',
  }));
  await assertFails(updateDoc(doc(verified('bob'), 'profiles/alice'), {
    nickname: '빼앗음',
  }));
  await assertFails(updateDoc(doc(alice, 'profiles/alice'), {
    isAdmin: true,
  }));
});
