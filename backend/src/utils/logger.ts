import pino from "pino";
import { getEnv } from "../config/env.js";

const env = getEnv();

export const logger = pino({
  level: env.LOG_LEVEL,
  transport: env.LOG_PRETTY
    ? {
        target: "pino-pretty",
        options: {
          colorize: true,
          translateTime: "SYS:standard",
          ignore: "pid,hostname",
        },
      }
    : undefined,
  formatters: {
    level: (label) => {
      return { level: label };
    },
  },
  timestamp: () => `,"timestamp":"${new Date().toISOString()}"`,
});

export function createChildLogger(context: Record<string, unknown>) {
  return logger.child(context);
}

export function logRequest(req: {
  method: string;
  url: string;
  ip?: string;
  headers: Record<string, unknown>;
}) {
  logger.info({
    msg: "Incoming request",
    method: req.method,
    url: req.url,
    ip: req.ip,
    userAgent: req.headers["user-agent"],
  });
}

export function logResponse(req: {
  method: string;
  url: string;
  statusCode?: number;
}) {
  return (statusCode: number, responseTime: number) => {
    logger.info({
      msg: "Request completed",
      method: req.method,
      url: req.url,
      statusCode,
      responseTimeMs: responseTime,
    });
  };
}
