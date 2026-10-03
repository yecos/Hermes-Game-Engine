import { defineConfig } from "@neon/config/v1";

export default defineConfig({
  buckets: {
    "hge-assets": { access: "public_read" },
  },
});
