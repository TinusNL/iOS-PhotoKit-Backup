import { timingSafeEqual } from "node:crypto";
import type { ApiKeyConfig } from "./config.ts";

export function authenticate(authorization: string | undefined, keys: ApiKeyConfig[]): ApiKeyConfig | undefined {
  if (!authorization) {
    return undefined;
  }
  const match = /^Bearer\s+(\S+)\s*$/i.exec(authorization);
  if (!match) {
    return undefined;
  }
  const token = match[1];
  return keys.find((entry) => safeEqual(entry.apiKey, token));
}

function safeEqual(left: string, right: string): boolean {
  const leftBuffer = Buffer.from(left);
  const rightBuffer = Buffer.from(right);
  if (leftBuffer.length !== rightBuffer.length) {
    return false;
  }
  return timingSafeEqual(leftBuffer, rightBuffer);
}
