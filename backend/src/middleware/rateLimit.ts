import rateLimit from "express-rate-limit";
import { getEnv } from "../config/env.js";

export function createRateLimiter() {
  const env = getEnv();
  
  return rateLimit({
    windowMs: env.RECIPE_FETCH_RATE_WINDOW_MS,
    max: env.RECIPE_FETCH_RATE_MAX,
    standardHeaders: true,
    legacyHeaders: false,
    message: {
      error: "rate_limited",
      message: "Too many requests, please try again later",
      retryInSeconds: Math.ceil(env.RECIPE_FETCH_RATE_WINDOW_MS / 1000),
    },
    keyGenerator: (req) => {
      const forwarded = req.headers["x-forwarded-for"];
      if (typeof forwarded === "string") {
        return forwarded.split(",")[0]!.trim();
      }
      return req.ip ?? "unknown";
    },
  });
}

export function createBarcodeRateLimiter() {
  const env = getEnv();
  
  return rateLimit({
    windowMs: env.BARCODE_LOOKUP_RATE_WINDOW_MS,
    max: env.BARCODE_LOOKUP_RATE_MAX,
    standardHeaders: true,
    legacyHeaders: false,
    message: {
      error: "rate_limited",
      message: "Too many barcode lookups, please try again later",
      retryInSeconds: Math.ceil(env.BARCODE_LOOKUP_RATE_WINDOW_MS / 1000),
    },
  });
}
