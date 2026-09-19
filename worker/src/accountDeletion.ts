export type AccountDeletionEnv = {
  AI_DB: D1Database;
};

export async function accountIsDeleted(uid: string, env: AccountDeletionEnv): Promise<boolean> {
  const row = await env.AI_DB.prepare(
    "SELECT status FROM account_deletions WHERE uid = ?"
  ).bind(uid).first<{status: string}>();
  return row?.status === "deleting" || row?.status === "completed";
}

export async function deleteAccountData(uid: string, env: AccountDeletionEnv): Promise<void> {
  const now = Date.now();
  await env.AI_DB.prepare(
    `INSERT INTO account_deletions (uid, status, requested_at_ms, completed_at_ms)
     VALUES (?, 'deleting', ?, NULL)
     ON CONFLICT(uid) DO UPDATE SET status = 'deleting'`
  ).bind(uid, now).run();

  await env.AI_DB.batch([
    env.AI_DB.prepare(
      "DELETE FROM ai_provider_calls WHERE generation_id IN (SELECT id FROM ai_generations WHERE uid = ?)"
    ).bind(uid),
    env.AI_DB.prepare("DELETE FROM ai_generations WHERE uid = ?").bind(uid),
    env.AI_DB.prepare("DELETE FROM ai_monthly_usage WHERE uid = ?").bind(uid),
    env.AI_DB.prepare("DELETE FROM ai_free_quota WHERE uid = ?").bind(uid)
  ]);

  await env.AI_DB.prepare(
    "UPDATE account_deletions SET status = 'completed', completed_at_ms = ? WHERE uid = ?"
  ).bind(Date.now(), uid).run();
}
