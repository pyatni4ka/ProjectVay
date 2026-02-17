export type PriceQuote = {
  priceRub: number;
  confidence: number;
  source: string;
};

export interface PriceProvider {
  id: string;
  quote(ingredientKey: string): Promise<PriceQuote | null>;
}
