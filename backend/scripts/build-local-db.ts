import https from "node:https";
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import readline from "node:readline";
import Database from "better-sqlite3";
import { fileURLToPath } from "node:url";

import { Readable } from "node:stream";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const DATA_DIR = path.join(__dirname, "../data");
const DB_PATH = path.join(DATA_DIR, "local_barcode_db.sqlite");
const CSV_GZ_URL = "https://static.openfoodfacts.org/data/en.openfoodfacts.org.products.csv.gz";

if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
}

// Function to safely extract a column index
function getColumnIndex(headers: string[], name: string): number {
    return headers.indexOf(name);
}

async function buildDatabase() {
    console.log("Removing old database if exists...");
    if (fs.existsSync(DB_PATH)) fs.unlinkSync(DB_PATH);

    const db = new Database(DB_PATH);

    // Create table
    db.exec(`
    CREATE TABLE products (
      barcode TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      brand TEXT,
      category TEXT
    );
  `);

    console.log("Created table schema.");

    const insert = db.prepare(
        `INSERT OR IGNORE INTO products (barcode, name, brand, category) VALUES (?, ?, ?, ?)`
    );

    console.log(`Downloading and streaming OpenFoodFacts data...`);

    const response = await fetch(CSV_GZ_URL);
    if (!response.ok || !response.body) {
        throw new Error(`Failed to download: ${response.status} ${response.statusText}`);
    }

    const fileStream = Readable.fromWeb(response.body as any);

    return new Promise<void>((resolve, reject) => {
        const gunzip = zlib.createGunzip();
        fileStream.pipe(gunzip);

        const rl = readline.createInterface({
            input: gunzip,
            crlfDelay: Infinity,
        });

        let headers: string[] | null = null;
        let count = 0;
        let inserted = 0;

        let idxCode = -1;
        let idxName = -1;
        let idxNameRu = -1;
        let idxBrands = -1;
        let idxCategories = -1;
        let idxCountriesTags = -1;

        // Wrap inserts in a transaction for mass performance
        db.exec("BEGIN");

        rl.on("line", (line: string) => {
            const cols = line.split("\t");

            if (!headers) {
                headers = cols;
                idxCode = getColumnIndex(headers, "code");
                idxName = getColumnIndex(headers, "product_name");
                idxNameRu = getColumnIndex(headers, "product_name_ru");
                idxBrands = getColumnIndex(headers, "brands");
                idxCategories = getColumnIndex(headers, "categories");
                idxCountriesTags = getColumnIndex(headers, "countries_tags");
                return;
            }

            count++;

            const code = cols[idxCode];
            const nameRu = idxNameRu >= 0 ? cols[idxNameRu] : "";
            let name = idxName >= 0 ? cols[idxName] : "";
            const brands = idxBrands >= 0 ? cols[idxBrands] : "";
            const categories = idxCategories >= 0 ? cols[idxCategories] : "";
            const countriesTags = idxCountriesTags >= 0 ? cols[idxCountriesTags] : "";

            if (!code) return; // Must have barcode

            // Heuristic for Russian product
            const isFromRussia = countriesTags.includes("en:russia") || countriesTags.includes("ru:");

            let finalName = nameRu.trim();
            if (!finalName) finalName = name.trim();

            if (!finalName) return; // Must have a name

            // We only insert if it's explicitly Russian or has a valid RU name
            // Many generic global products have Russian tags too
            if (isFromRussia || nameRu.trim().length > 0) {
                insert.run(code, finalName.substring(0, 200), brands.substring(0, 100), categories.substring(0, 100));
                inserted++;
            }

            if (count % 100000 === 0) {
                console.log(`Parsed ${count} rows...Inserted ${inserted} relevant products.`);
                // Commit and start new transaction to keep memory low
                db.exec("COMMIT");
                db.exec("BEGIN");
            }
        });

        rl.on("close", () => {
            db.exec("COMMIT");

            console.log(`Finished parsing.Total processed: ${count}, Total inserted: ${inserted}.`);
            console.log("Optimizing database...");
            db.exec("VACUUM"); // Compact the database
            db.close();

            console.log(`Success! Offline DB generated at ${DB_PATH}`);
            resolve();
        });

        rl.on("error", (err: Error) => {
            db.exec("ROLLBACK");
            db.close();
            reject(err);
        });
        gunzip.on("error", (err: Error) => reject(err));
        fileStream.on("error", (err: Error) => reject(err));
    });
}

buildDatabase().catch((e) => {
    console.error("Error building db:", e);
    process.exit(1);
});
