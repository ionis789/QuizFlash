import {defineWorkersConfig} from "@cloudflare/vitest-pool-workers/config";
import {readD1Migrations} from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig(async () => ({
  test: {
    setupFiles: ["./test/applyMigrations.ts"],
    poolOptions: {
      workers: {
        wrangler: {configPath: "./wrangler.jsonc"},
        miniflare: {
          bindings: {
            TEST_MIGRATIONS: await readD1Migrations("./migrations")
          }
        }
      }
    }
  }
}));
