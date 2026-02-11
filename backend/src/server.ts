import express from "express";
import routes from "./api/routes.js";

const app = express();
app.use(express.json({ limit: "256kb" }));

app.get("/health", (_req, res) => {
  res.json({ ok: true });
});

app.use("/api/v1", routes);

app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error(err);
  res.status(500).json({ error: "internal_error" });
});

const port = Number(process.env.PORT ?? 8080);
app.listen(port, () => {
  console.log(`Backend started on :${port}`);
});
