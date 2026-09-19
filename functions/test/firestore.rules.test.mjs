import { after, before, beforeEach, test } from "node:test";
import { readFile } from "node:fs/promises";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  deleteField,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
} from "firebase/firestore";

const projectId = "quizflash-rules-test";
let testEnvironment;

before(async () => {
  testEnvironment = await initializeTestEnvironment({
    projectId,
    firestore: {
      rules: await readFile(new URL("../../firestore.rules", import.meta.url), "utf8"),
    },
  });
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
});

after(async () => {
  await testEnvironment.cleanup();
});

function userDocument(context, uid = "alice") {
  return doc(context.firestore(), "users", uid);
}

async function seedUser() {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(userDocument(context), {
      email: "alice@example.com",
      displayName: "Alice",
      providers: ["apple.com"],
      updatedAt: new Date(),
      plan: "free",
      premium: false,
      freeGenerationsUsed: 1,
    });
  });
}

test("owner can create and update only profile fields", async () => {
  const alice = testEnvironment.authenticatedContext("alice");

  await assertSucceeds(setDoc(userDocument(alice), {
    email: "alice@example.com",
    displayName: "Alice",
    photoURL: "https://example.com/avatar.png",
    providers: ["apple.com"],
    updatedAt: serverTimestamp(),
  }));

  await assertSucceeds(updateDoc(userDocument(alice), {
    displayName: "Alice Updated",
    updatedAt: serverTimestamp(),
  }));
});

test("client cannot create a server-owned field", async () => {
  const alice = testEnvironment.authenticatedContext("alice");

  await assertFails(setDoc(userDocument(alice), {
    email: "alice@example.com",
    plan: "premium",
  }));
});

test("client cannot add, change, or remove server-owned fields", async () => {
  await seedUser();
  const alice = testEnvironment.authenticatedContext("alice");

  await assertFails(updateDoc(userDocument(alice), { aiUsage: 0 }));
  await assertFails(updateDoc(userDocument(alice), { plan: "premium" }));
  await assertFails(updateDoc(userDocument(alice), { premium: deleteField() }));

  await assertSucceeds(getDoc(userDocument(alice)));
});

test("users cannot access another user's profile", async () => {
  await seedUser();
  const bob = testEnvironment.authenticatedContext("bob");

  await assertFails(getDoc(userDocument(bob, "alice")));
  await assertFails(updateDoc(userDocument(bob, "alice"), { displayName: "Bob" }));
});
