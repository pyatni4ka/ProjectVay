import type { IngestionAdapter } from "./types.js";
import { offAdapter } from "./adapters/off.js";
import { catalogAdapter } from "./adapters/catalog.js";
import { uhttAdapter } from "./adapters/uhtt.js";
import { foodRuAdapter } from "./adapters/foodru.js";
import { edaRuAdapter } from "./adapters/edaru.js";
import { povarRuAdapter } from "./adapters/povarru.js";
import { magnitAdapter } from "./adapters/magnit.js";
import { pyaterochkaAdapter } from "./adapters/pyaterochka.js";

export const ingestionSourceRegistry: IngestionAdapter[] = [
  offAdapter,
  catalogAdapter,
  uhttAdapter,
  foodRuAdapter,
  edaRuAdapter,
  povarRuAdapter,
  magnitAdapter,
  pyaterochkaAdapter
];
