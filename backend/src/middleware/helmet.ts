import helmet from "helmet";
import { getEnv } from "../config/env.js";

export function createHelmet() {
  const env = getEnv();
  
  return helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        scriptSrc: ["'self'"],
        styleSrc: ["'self'", "'unsafe-inline'"],
        imgSrc: ["'self'", "data:", "https:"],
        connectSrc: ["'self'", "https://world.openfoodfacts.org"],
        fontSrc: ["'self'"],
      },
    },
    hsts: env.NODE_ENV === "production" ? {
      maxAge: 31536000,
      includeSubDomains: true,
      preload: true,
    } : false,
  });
}
