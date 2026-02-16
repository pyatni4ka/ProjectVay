import express from "express";
import { initEnv } from "./config/env.js";
import { createHelmet } from "./middleware/helmet.js";
import { createCors } from "./middleware/cors.js";
import { createRateLimiter } from "./middleware/rateLimit.js";
import { errorHandler, notFoundHandler } from "./middleware/error.js";
import { logger } from "./utils/logger.js";
import healthRoutes from "./routes/health.js";
import v1Routes from "./routes/v1/index.js";

declare global {
  namespace Express {
    interface Request {
      requestTime?: number;
    }
  }
}

initEnv();

const app = express();
const env = initEnv();

app.use(express.json({ limit: "256kb" }));

app.use(createHelmet());
app.use(createCors());

app.use((req, res, next) => {
  req.requestTime = Date.now();
  logger.info({
    msg: "Incoming request",
    method: req.method,
    url: req.url,
    ip: req.ip,
  });
  next();
});

app.use(healthRoutes);
app.use("/api/v1", createRateLimiter(), v1Routes);

app.use(notFoundHandler);
app.use(errorHandler);

const server = app.listen(env.PORT, () => {
  logger.info({
    msg: "Server started",
    port: env.PORT,
    environment: env.NODE_ENV,
  });
});

function gracefulShutdown(signal: string) {
  logger.info({
    msg: "Graceful shutdown initiated",
    signal,
  });

  server.close((err) => {
    if (err) {
      logger.error({
        msg: "Error during shutdown",
        error: err.message,
      });
      process.exit(1);
    }

    logger.info({
      msg: "Server closed gracefully",
    });
    process.exit(0);
  });

  setTimeout(() => {
    logger.error({
      msg: "Forced shutdown after timeout",
    });
    process.exit(1);
  }, 10000);
}

process.on("SIGTERM", () => gracefulShutdown("SIGTERM"));
process.on("SIGINT", () => gracefulShutdown("SIGINT"));

export default app;
