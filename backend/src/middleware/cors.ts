import cors from "cors";
import { getEnv } from "../config/env.js";

export function createCors() {
  const env = getEnv();
  
  return cors({
    origin: env.CORS_ORIGIN,
    methods: ["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allowedHeaders: ["Content-Type", "Authorization", "X-Request-ID"],
    credentials: true,
    maxAge: 86400,
  });
}
