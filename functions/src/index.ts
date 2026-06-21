import {initializeApp} from "firebase-admin/app";
import {getAuth} from "firebase-admin/auth";
import {FieldValue, getFirestore, Timestamp} from "firebase-admin/firestore";
import type {CollectionReference} from "firebase-admin/firestore";
import {HttpsError, onCall} from "firebase-functions/v2/https";
import {defineInt, defineSecret, defineString} from "firebase-functions/params";

initializeApp();

const deepSeekAPIKey = defineSecret("DEEPSEEK_API_KEY");
const deepSeekBaseURL = defineString("DEEPSEEK_BASE_URL", {default: "https://api.deepseek.com"});
const deepSeekModel = defineString("DEEPSEEK_MODEL", {default: "deepseek-chat"});
const premiumMonthlyAIBudgetCents = defineInt("PREMIUM_MONTHLY_AI_BUDGET_CENTS", {default: 200});

const freeLifetimeGenerationLimit = 5;
const freeMaxCardsPerGeneration = 30;
const premiumMaxCardsPerGeneration = 100;

type GenerateDeckRequest = {
  source?: {
    kind?: string;
    text?: string;
  };
  targetCards?: number;
  options?: {
    cardType?: string;
    cardLevel?: string;
    outputLanguageMode?: string;
    manualOutputLanguage?: {
      languageCode?: string;
      displayName?: string;
    };
  };
};

type DeckJSONCardDTO = Record<string, unknown>;

type DeckJSONCardBatchDTO = {
  schemaVersion: number;
  cards: DeckJSONCardDTO[];
};

const db = getFirestore();

export const upsertUserProfile = onCall({enforceAppCheck: false}, async (request) => {
  const uid = requireUID(request.auth?.uid);
  const data = request.data as Record<string, unknown>;

  await db.collection("users").doc(uid).set({
    email: stringOrNull(data.email),
    displayName: stringOrNull(data.displayName),
    photoURL: stringOrNull(data.photoURL),
    providers: Array.isArray(data.providers) ? data.providers.filter((value) => typeof value === "string") : [],
    freeGenerationsLimit: freeLifetimeGenerationLimit,
    updatedAt: FieldValue.serverTimestamp(),
    createdAt: FieldValue.serverTimestamp()
  }, {merge: true});

  return {ok: true};
});

export const generateDeck = onCall({
  enforceAppCheck: false,
  secrets: [deepSeekAPIKey],
  timeoutSeconds: 300,
  memory: "512MiB"
}, async (request) => {
  const uid = requireUID(request.auth?.uid);
  const payload = request.data as GenerateDeckRequest;
  const sourceText = payload.source?.text?.trim() ?? "";
  const targetCards = safeTargetCards(payload.targetCards);

  if (!sourceText) {
    throw new HttpsError("invalid-argument", "Source text is required.");
  }

  const userRef = db.collection("users").doc(uid);
  const usageRef = userRef.collection("usage").doc(monthKey(new Date()));
  const userSnapshot = await userRef.get();
  const user = userSnapshot.data() ?? {};
  const premium = request.auth?.token.premium === true || user.premium === true || user.plan === "premium";
  const maxCards = premium ? premiumMaxCardsPerGeneration : freeMaxCardsPerGeneration;

  if (targetCards > maxCards) {
    throw new HttpsError("failed-precondition", `This plan allows up to ${maxCards} cards per generation.`);
  }

  if (!premium) {
    const used = numberOrZero(user.freeGenerationsUsed);
    if (used >= freeLifetimeGenerationLimit) {
      throw new HttpsError("resource-exhausted", "Free AI generation limit reached.");
    }
  }

  const usageSnapshot = await usageRef.get();
  const currentMonthlyCost = numberOrZero(usageSnapshot.data()?.costCents);
  if (premium && currentMonthlyCost >= premiumMonthlyAIBudgetCents.value()) {
    throw new HttpsError("resource-exhausted", "Monthly AI budget reached.");
  }

  const batch = await callDeepSeekForCards(sourceText, targetCards, payload.options);
  const deckID = db.collection("users").doc(uid).collection("decks").doc().id;
  const now = Timestamp.now();
  const deckRef = userRef.collection("decks").doc(deckID);
  const writeBatch = db.batch();

  writeBatch.set(deckRef, {
    schemaVersion: 1,
    title: null,
    colorHex: "#6D5DF6",
    createdAt: now,
    editedAt: now,
    cardCount: batch.cards.length,
    syncRevision: 1,
    generatedBy: "cloudAI",
    updatedAt: FieldValue.serverTimestamp()
  }, {merge: true});

  batch.cards.forEach((card, index) => {
    const cardRef = deckRef.collection("cards").doc();
    writeBatch.set(cardRef, {
      schemaVersion: 1,
      creationSource: "ai",
      createdAt: now,
      editedAt: now,
      cardNumber: index + 1,
      isPinned: false,
      syncRevision: 1,
      payload: card,
      updatedAt: FieldValue.serverTimestamp()
    }, {merge: true});
  });

  if (!premium) {
    writeBatch.set(userRef, {
      freeGenerationsUsed: FieldValue.increment(1),
      freeGenerationsLimit: freeLifetimeGenerationLimit,
      updatedAt: FieldValue.serverTimestamp()
    }, {merge: true});
  }

  writeBatch.set(usageRef, {
    generatedCards: FieldValue.increment(batch.cards.length),
    requestCount: FieldValue.increment(1),
    costCents: FieldValue.increment(0),
    updatedAt: FieldValue.serverTimestamp()
  }, {merge: true});

  await writeBatch.commit();

  return {
    deckID,
    title: null,
    cards: batch.cards,
    freeGenerationsUsed: premium ? null : numberOrZero(user.freeGenerationsUsed) + 1,
    freeGenerationsLimit: premium ? null : freeLifetimeGenerationLimit
  };
});

export const deleteUserData = onCall({enforceAppCheck: false}, async (request) => {
  const uid = requireUID(request.auth?.uid);
  await getAuth().getUser(uid);
  await deleteDecks(uid);
  await deleteCollection(db.collection("users").doc(uid).collection("usage"), 100);
  await db.collection("users").doc(uid).delete();
  return {ok: true};
});

function requireUID(uid: string | undefined): string {
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in is required.");
  }
  return uid;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

function numberOrZero(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function safeTargetCards(value: unknown): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 1) {
    throw new HttpsError("invalid-argument", "Target card count is invalid.");
  }
  return value;
}

function monthKey(date: Date): string {
  return `${date.getUTCFullYear()}${String(date.getUTCMonth() + 1).padStart(2, "0")}`;
}

async function callDeepSeekForCards(
  sourceText: string,
  targetCards: number,
  options: GenerateDeckRequest["options"]
): Promise<DeckJSONCardBatchDTO> {
  const response = await fetch(`${deepSeekBaseURL.value().replace(/\/$/, "")}/chat/completions`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${deepSeekAPIKey.value()}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: deepSeekModel.value(),
      response_format: {type: "json_object"},
      messages: [
        {
          role: "system",
          content: systemPrompt(options)
        },
        {
          role: "user",
          content: `Create exactly ${targetCards} cards from this source:\n\n${sourceText.slice(0, 60000)}`
        }
      ]
    })
  });

  if (!response.ok) {
    throw new HttpsError("internal", `DeepSeek request failed: ${response.status}`);
  }

  const body = await response.json() as {
    choices?: Array<{message?: {content?: string}}>;
  };
  const content = body.choices?.[0]?.message?.content;
  if (!content) {
    throw new HttpsError("internal", "DeepSeek returned an empty response.");
  }

  const parsed = JSON.parse(content) as DeckJSONCardBatchDTO;
  if (parsed.schemaVersion !== 1 || !Array.isArray(parsed.cards) || parsed.cards.length === 0) {
    throw new HttpsError("internal", "DeepSeek returned an invalid deck schema.");
  }

  return parsed;
}

function systemPrompt(options: GenerateDeckRequest["options"]): string {
  const cardType = options?.cardType === "quiz" ? "quiz" : "flashcard";
  const level = options?.cardLevel === "simple" ? "simple" : "pro";
  const languageInstruction = options?.outputLanguageMode === "manual" && options.manualOutputLanguage?.displayName ?
    `Write in ${options.manualOutputLanguage.displayName}.` :
    "Use the same language as the source.";

  return [
    "Return only valid JSON.",
    "Use schemaVersion 1.",
    `Generate ${cardType} cards with ${level} depth.`,
    languageInstruction,
    "For flashcards, each card must be {\"type\":\"flashcard\",\"front\":{\"zones\":[...]},\"back\":{\"zones\":[...]},\"frontType\":\"text\",\"backType\":\"text\"}.",
    "For quiz cards, each card must be {\"type\":\"quiz\",\"question\":{\"zones\":[...]},\"choices\":[{\"zones\":[...],\"isCorrect\":true}],\"explanation\":{\"zones\":[...]},\"allowsMultipleCorrect\":false}.",
    "Each zone is {\"id\":\"UUID\",\"type\":\"text\",\"text\":\"...\",\"textStyle\":\"body\",\"sizeMode\":\"auto\",\"blockAlignment\":\"leading\",\"verticalAlignment\":\"center\",\"textColor\":\"primary\",\"isBold\":false,\"isItalic\":false,\"fontFamily\":\"system\",\"highlightColor\":\"none\",\"imageScale\":1}.",
    "The root JSON shape must be {\"schemaVersion\":1,\"cards\":[...]}."
  ].join("\n");
}

async function deleteCollection(
  collection: CollectionReference,
  batchSize: number
): Promise<void> {
  while (true) {
    const snapshot = await collection.limit(batchSize).get();
    if (snapshot.empty) {
      return;
    }

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }
}

async function deleteDecks(uid: string): Promise<void> {
  const decks = await db.collection("users").doc(uid).collection("decks").get();
  for (const deck of decks.docs) {
    await deleteCollection(deck.ref.collection("cards"), 100);
    await deck.ref.delete();
  }
}
