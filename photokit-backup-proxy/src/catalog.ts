import { readdir, stat } from "node:fs/promises";
import { join, relative, resolve, sep } from "node:path";
import { filenameKey } from "./filenames.ts";

export interface StoredFile {
  filename: string;
  relativePath: string;
  fullPath: string;
  bytes: number;
  modifiedAt: Date;
}

interface CatalogSnapshot {
  byName: Map<string, StoredFile>;
  files: StoredFile[];
  scannedAt: number;
}

const cache = new Map<string, CatalogSnapshot>();

export function invalidateCatalog(directory: string): void {
  cache.delete(resolve(directory));
}

export async function catalogFiles(directory: string, maxAgeMs = 5_000): Promise<CatalogSnapshot> {
  const root = resolve(directory);
  const cached = cache.get(root);
  if (cached && Date.now() - cached.scannedAt < maxAgeMs) {
    return cached;
  }

  const files: StoredFile[] = [];
  await walk(root, root, files);
  files.sort((left, right) => right.modifiedAt.getTime() - left.modifiedAt.getTime());

  const byName = new Map<string, StoredFile>();
  for (const file of files) {
    const key = filenameKey(file.filename);
    const current = byName.get(key);
    if (!current || file.modifiedAt > current.modifiedAt) {
      byName.set(key, file);
    }
  }

  const snapshot = { byName, files, scannedAt: Date.now() };
  cache.set(root, snapshot);
  return snapshot;
}

export function rememberFile(directory: string, file: StoredFile): void {
  const root = resolve(directory);
  const snapshot = cache.get(root);
  if (!snapshot) {
    return;
  }
  snapshot.files.unshift(file);
  snapshot.byName.set(filenameKey(file.filename), file);
  snapshot.scannedAt = Date.now();
}

export function findExisting(snapshot: CatalogSnapshot, filename: string, relativePath: string): StoredFile | undefined {
  const byName = snapshot.byName.get(filenameKey(filename));
  if (byName) {
    return byName;
  }
  const normalized = normalizeRelative(relativePath);
  if (!normalized) {
    return undefined;
  }
  return snapshot.files.find((file) => file.relativePath === normalized);
}

export function resolveInside(directory: string, relativePath: string): string | undefined {
  const normalized = normalizeRelative(relativePath);
  if (!normalized) {
    return undefined;
  }
  const root = resolve(directory);
  const full = resolve(root, normalized);
  if (full !== root && !full.startsWith(root + sep)) {
    return undefined;
  }
  return full;
}

function normalizeRelative(relativePath: string): string | undefined {
  const normalized = relativePath.replaceAll("\\", "/").replace(/^\/+/, "");
  if (!normalized || normalized.includes("\0")) {
    return undefined;
  }
  const parts = normalized.split("/");
  if (parts.some((part) => part === "" || part === "." || part === ".." || part.startsWith("."))) {
    return undefined;
  }
  return parts.join("/");
}

async function walk(directory: string, root: string, into: StoredFile[]): Promise<void> {
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    if (entry.name.startsWith(".")) {
      continue;
    }
    const fullPath = join(directory, entry.name);
    if (entry.isDirectory()) {
      await walk(fullPath, root, into);
      continue;
    }
    if (!entry.isFile()) {
      continue;
    }
    const info = await stat(fullPath);
    if (info.size <= 0) {
      continue;
    }
    into.push({
      filename: entry.name,
      relativePath: relative(root, fullPath).split(sep).join("/"),
      fullPath,
      bytes: info.size,
      modifiedAt: info.mtime,
    });
  }
}
