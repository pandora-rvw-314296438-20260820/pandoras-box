import express from "express";

const growthMemory = require("../../src/pandora-growth-memory-http.js") as {
  createPandoraGrowthMemoryRouter: () => any;
};

export const config = { maxDuration: 60 };

const app = express();
app.use(growthMemory.createPandoraGrowthMemoryRouter());

export default app;
