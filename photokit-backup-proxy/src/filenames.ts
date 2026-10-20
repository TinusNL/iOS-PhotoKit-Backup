import { basename } from "node:path";

const RESOURCE_TYPES = new Set(["photo", "pairedVideo", "video"]);

export function isResourceType(value: string): boolean {
  return RESOURCE_TYPES.has(value);
}

export function yearMonth(createdAt: string | undefined, now = new Date()): { year: string; month: string } {
  if (createdAt) {
    const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(createdAt.trim());
    if (match) {
      const month = Number(match[2]);
      const day = Number(match[3]);
      if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
        return { year: match[1], month: match[2] };
      }
    }
  }

  return {
    year: String(now.getUTCFullYear()),
    month: String(now.getUTCMonth() + 1).padStart(2, "0"),
  };
}

export function relativeStoragePath(filename: string, createdAt: string | undefined, now = new Date()): string {
  const { year, month } = yearMonth(createdAt, now);
  return `${year}/${month}/${filename}`;
}

export function decodeFilename(header: string): string {
  const trimmed = header.trim();
  if (!trimmed.includes("%")) {
    return sanitizeFilename(trimmed);
  }
  try {
    return sanitizeFilename(decodeURIComponent(trimmed));
  } catch {
    return sanitizeFilename(trimmed);
  }
}

export function sanitizeFilename(input: string): string {
  const base = basename(input.replaceAll("\\", "/")).replace(/[\u0000-\u001f]/g, "");
  const cleaned = base.replace(/^\.+/, "").slice(0, 240);
  if (!cleaned || cleaned === "." || cleaned === "..") {
    return "upload.bin";
  }
  return cleaned;
}

export function filenameKey(filename: string): string {
  return filename.normalize("NFC").toLowerCase();
}
