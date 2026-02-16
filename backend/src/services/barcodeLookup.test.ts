import { describe, it } from 'node:test';
import assert from 'node:assert';
import { parseBarcodeListRuHTML } from './barcodeLookup.js';

describe('parseBarcodeListRuHTML', () => {
    it('should return null for generic "Not Found" page title', () => {
        const html = `
      <html>
        <head>
          <title>Штрихкод 4607001771562 - Штрих-код: 4607001771562</title>
          <meta property="og:title" content="Штрихкод 4607001771562 - Штрих-код: 4607001771562" />
        </head>
        <body>
          <h1>Штрих-код: 4607001771562</h1>
          <p>Product description not found.</p>
        </body>
      </html>
    `;
        const result = parseBarcodeListRuHTML(html, '4607001771562');
        assert.strictEqual(result, null);
    });

    it('should return null for "Поиск" title', () => {
        const html = `
      <html>
        <head>
          <title>Поиск</title>
        </head>
        <body>
            <h1>Поиск</h1>
        </body>
      </html>
    `;
        const result = parseBarcodeListRuHTML(html, '4607001771562');
        assert.strictEqual(result, null);
    });

    it('should extract valid product name', () => {
        const html = `
      <html>
        <head>
          <title>Штрихкод 4607001771562 - Real Product Name</title>
          <meta property="og:title" content="Штрихкод 4607001771562 - Real Product Name" />
        </head>
        <body>
          <h1>Real Product Name</h1>
        </body>
      </html>
    `;
        const result = parseBarcodeListRuHTML(html, '4607001771562');
        assert.strictEqual(result?.name, 'Real Product Name');
    });
});
