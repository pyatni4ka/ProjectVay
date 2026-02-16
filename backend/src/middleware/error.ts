import type { Request, Response, NextFunction } from "express";
import { ZodError } from "zod";
import { logger } from "../utils/logger.js";

export class AppError extends Error {
  public readonly statusCode: number;
  public readonly isOperational: boolean;
  public readonly code?: string;

  constructor(message: string, statusCode: number, code?: string) {
    super(message);
    this.statusCode = statusCode;
    this.isOperational = true;
    this.code = code;
    Error.captureStackTrace(this, this.constructor);
  }
}

export function errorHandler(
  err: Error,
  _req: Request,
  res: Response,
  _next: NextFunction
) {
  if (err instanceof ZodError) {
    logger.warn({
      msg: "Validation error",
      errors: err.errors,
    });
    
    return res.status(400).json({
      error: "validation_error",
      message: "Invalid request data",
      details: err.errors.map((e) => ({
        path: e.path.join("."),
        message: e.message,
      })),
    });
  }

  if (err instanceof AppError) {
    logger.warn({
      msg: "Operational error",
      code: err.code,
      statusCode: err.statusCode,
      message: err.message,
    });
    
    return res.status(err.statusCode).json({
      error: err.code ?? "error",
      message: err.message,
    });
  }

  logger.error({
    msg: "Internal server error",
    error: err.message,
    stack: err.stack,
  });

  res.status(500).json({
    error: "internal_error",
    message: "An unexpected error occurred",
  });
}

export function notFoundHandler(_req: Request, res: Response) {
  res.status(404).json({
    error: "not_found",
    message: "The requested resource was not found",
  });
}

export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<void>
) {
  return (req: Request, res: Response, next: NextFunction) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}
