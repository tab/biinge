import { defineConfig } from "astro/config";
import { loadEnv } from "vite";

// The public domain is deployment config, not source: .env locally, a repository variable in CI
const { SITE_URL } = loadEnv(process.env.NODE_ENV ?? "", process.cwd(), "SITE_");

export default defineConfig({
  // An unset repository variable arrives as an empty string, which fails URL validation
  site: SITE_URL || undefined,
  base: "/",
});
