import type { LicenseRisk } from "./types.js";

const RISK_LEVEL: Record<LicenseRisk, number> = {
  low: 1,
  medium: 2,
  high: 3
};

export function isLicenseRiskAllowed(sourceRisk: LicenseRisk, allowedRisk: LicenseRisk): boolean {
  return RISK_LEVEL[sourceRisk] <= RISK_LEVEL[allowedRisk];
}

export function normalizeLicenseRisk(value: string | undefined, fallback: LicenseRisk = "high"): LicenseRisk {
  switch ((value ?? "").trim().toLowerCase()) {
    case "low":
      return "low";
    case "medium":
      return "medium";
    case "high":
      return "high";
    default:
      return fallback;
  }
}
