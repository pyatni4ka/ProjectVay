export const normalizeToken = (value: string): string => value.trim().toLowerCase();

export const overlapScore = (left: string[], right: string[]): number => {
  if (!left.length) return 0;
  const rightSet = new Set(right.map(normalizeToken));
  const hit = left.map(normalizeToken).filter((item) => rightSet.has(item)).length;
  return hit / left.length;
};

export const nutritionFit = (target: number | undefined, actual: number | undefined): number => {
  if (!target || !actual) return 0.5;
  const diff = Math.abs(target - actual) / Math.max(target, 1);
  return Math.max(0, Math.exp(-2 * diff));
};
