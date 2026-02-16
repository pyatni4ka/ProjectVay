import { z } from "zod";

const envSchema = z.object({
  NODE_ENV: z.enum(["development", "production", "test"]).default("development"),
  PORT: z.coerce.number().min(1).max(65535).default(8080),
  
  // Recipe cache
  RECIPE_CACHE_TTL_SECONDS: z.coerce.number().default(60 * 60 * 24 * 7),
  RECIPE_CACHE_DB_PATH: z.string().default("data/recipe-cache.sqlite"),
  
  // Rate limiting
  RECIPE_FETCH_RATE_WINDOW_MS: z.coerce.number().default(60_000),
  RECIPE_FETCH_RATE_MAX: z.coerce.number().default(30),
  BARCODE_LOOKUP_RATE_WINDOW_MS: z.coerce.number().default(60_000),
  BARCODE_LOOKUP_RATE_MAX: z.coerce.number().default(120),
  
  // Barcode lookup
  EAN_DB_API_KEY: z.string().optional(),
  EAN_DB_API_URL: z.string().url().optional(),
  BARCODE_ENABLE_OPEN_FOOD_FACTS: z
    .string()
    .transform((val) => val !== "false")
    .default("true"),
  BARCODE_LOOKUP_TIMEOUT_MS: z.coerce.number().default(3_000),
  
  // CORS
  CORS_ORIGIN: z.string().default("*"),
  
  // Logging
  LOG_LEVEL: z.enum(["debug", "info", "warn", "error"]).default("info"),
  LOG_PRETTY: z.string().transform((val) => val === "true").default("true"),
  
  // Recipe sources
  RECIPE_SOURCE_WHITELIST: z.string().optional(),

  // External recipe providers
  EDAMAM_APP_ID: z.string().optional(),
  EDAMAM_APP_KEY: z.string().optional(),
  SPOONACULAR_API_KEY: z.string().optional(),
  EXTERNAL_RECIPES_ENABLED: z.string().transform((val) => val !== "false").default("true"),
});

export type Env = z.infer<typeof envSchema>;

let env: Env;

export function getEnv(): Env {
  if (env) {
    return env;
  }

  const result = envSchema.safeParse(process.env);

  if (!result.success) {
    console.error("Invalid environment variables:");
    console.error(result.error.flatten().fieldErrors);
    throw new Error("Invalid environment configuration");
  }

  env = result.data;
  return env;
}

export function initEnv(): Env {
  const e = getEnv();
  
  if (e.NODE_ENV === "development") {
    console.log("Running in development mode");
    console.log("Port:", e.PORT);
  }
  
  return e;
}
