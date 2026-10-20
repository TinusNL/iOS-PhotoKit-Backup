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
const recentCache = new Map<string, { files: StoredFile[]; scannedAt: number }>();

const yearDirectory = /^\d{4}$/;
const monthDirectory = /^(?:0[1-9]|1[0-2])$/;

export function invalidateCatalog(directory: string): void {
  const root = resolve(directory);
  cache.delete(root);
  recentCache.delete(root);
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
  if (snapshot) {
    snapshot.files.unshift(file);
    snapshot.byName.set(filenameKey(file.filename), file);
    snapshot.scannedAt = Date.now();
  }
  const recent = recentCache.get(root);
  if (recent && isYearMonthFile(file.relativePath)) {
    recent.files.unshift(file);
    recent.scannedAt = Date.now();
  }
}

export async function recentFiles(directory: string, maxAgeMs = 5_000): Promise<StoredFile[]> {
  const root = resolve(directory);
  const cached = recentCache.get(root);
  if (cached && Date.now() - cached.scannedAt < maxAgeMs) {
    return cached.files;
  }

  const files = await collectYearMonthFiles(root);
  files.sort((left, right) => right.modifiedAt.getTime() - left.modifiedAt.getTime());
  recentCache.set(root, { files, scannedAt: Date.now() });
  return files;
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

function isYearMonthFile(relativePath: string): boolean {
  const parts = relativePath.split("/");
  return parts.length === 3 && yearDirectory.test(parts[0] ?? "") && monthDirectory.test(parts[1] ?? "") && (parts[2]?.length ?? 0) > 0;
}

async function collectYearMonthFiles(root: string): Promise<StoredFile[]> {
  const files: StoredFile[] = [];
  let years;
  try {
    years = await readdir(root, { withFileTypes: true });
  } catch {
    return files;
  }

  for (const year of years) {
    if (!year.isDirectory() || !yearDirectory.test(year.name)) {
      continue;
    }
    const yearPath = join(root, year.name);
    let months;
    try {
      months = await readdir(yearPath, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const month of months) {
      if (!month.isDirectory() || !monthDirectory.test(month.name)) {
        continue;
      }
      const monthPath = join(yearPath, month.name);
      let entries;
      try {
        entries = await readdir(monthPath, { withFileTypes: true });
      } catch {
        continue;
      }
      for (const entry of entries) {
        if (!entry.isFile() || entry.name.startsWith(".") || entry.name.startsWith("@")) {
          continue;
        }
        const fullPath = join(monthPath, entry.name);
        const info = await stat(fullPath);
        if (info.size <= 0) {
          continue;
        }
        files.push({
          filename: entry.name,
          relativePath: `${year.name}/${month.name}/${entry.name}`,
          fullPath,
          bytes: info.size,
          modifiedAt: info.mtime,
        });
      }
    }
  }
  return files;
}

async function walk(directory: string, root: string, into: StoredFile[]): Promise<void> {
  let entries;
  try {
    entries = await readdir(directory, { withFileTypes: true });
  } catch {
    return;
  }

  for (const entry of entries) {
    // Dot folders are temporary. @eaDir holds Synology Photos thumbnails and index files.
    if (entry.name.startsWith(".") || entry.name.startsWith("@")) {
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
