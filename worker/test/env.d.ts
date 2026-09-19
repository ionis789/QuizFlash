declare module "cloudflare:test" {
  interface ProvidedEnv {
    AI_DB: D1Database;
    TEST_MIGRATIONS: Array<{name: string; queries: string[]}>;
  }
}
