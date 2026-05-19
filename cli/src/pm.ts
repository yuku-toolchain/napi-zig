import { detect, getUserAgent } from "package-manager-detector/detect";

export const SUPPORTED_PMS = ["npm", "yarn", "pnpm", "bun"] as const;
export type Pm = (typeof SUPPORTED_PMS)[number];

export function isPm(value: string | null | undefined): value is Pm {
  return !!value && (SUPPORTED_PMS as readonly string[]).includes(value);
}

// Best-effort guess from lockfiles + user agent. Falls back to "npm".
export async function detectPm(initial?: string): Promise<Pm> {
  if (isPm(initial)) return initial;
  const detected = await detect().catch(() => null);
  if (isPm(detected?.name)) return detected.name;
  const ua = getUserAgent();
  if (isPm(ua)) return ua;
  return "npm";
}
