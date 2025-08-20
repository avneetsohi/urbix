import express from "express";
import dotenv from "dotenv";
dotenv.config();

const app = express();
app.get("/healthz", (_req, res) => res.json({ ok: true }));

const port = process.env.PORT || 8080;
app.listen(port, () => console.log(`API listening on ${port}`));