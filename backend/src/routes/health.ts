import { Router } from "express";
import os from "os";
import { getEnv } from "../config/env.js";

const router = Router();

router.get("/health", (_req, res) => {
  const env = getEnv();
  
  const health = {
    status: "healthy",
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    environment: env.NODE_ENV,
    memory: {
      used: Math.round(process.memoryUsage().heapUsed / 1024 / 1024),
      total: Math.round(process.memoryUsage().heapTotal / 1024 / 1024),
    },
    cpu: {
      cores: os.cpus().length,
      load: os.loadavg(),
    },
    version: process.env.npm_package_version ?? "0.2.0",
  };

  res.json(health);
});

router.get("/health/ready", (_req, res) => {
  res.json({
    ready: true,
    timestamp: new Date().toISOString(),
  });
});

router.get("/health/live", (_req, res) => {
  res.json({
    alive: true,
    timestamp: new Date().toISOString(),
  });
});

export default router;
