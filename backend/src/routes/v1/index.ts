import { Router } from "express";
import recipesRouter from "./recipes.js";

const router = Router();

router.use("/", recipesRouter);

export default router;
