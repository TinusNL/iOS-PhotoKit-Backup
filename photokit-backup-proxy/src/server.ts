import { randomUUID } from "node:crypto";
import { createWriteStream } from "node:fs";
import { mkdir, rename, rm, stat } from "node:fs/promises";
import { type IncomingMessage, type Server, type ServerResponse, createServer } from "node:http";
import { extname, join } from "node:path";
import { pipeline } from "node:stream/promises";
import type { ApiKeyConfig, AppConfig } from "./config.ts";
import { authenticate } from "./auth.ts";
import { catalogFiles, findExisting, invalidateCatalog, recentFiles, rememberFile, resolveInside, type StoredFile } from "./catalog.ts";
import { decodeFilename, isResourceType, relativeStoragePath } from "./filenames.ts";

const LOOKUP_LIMIT = 5_000;
const BODY_LIMIT = 1_048_576;

class HttpError extends Error {
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

const directoryLocks = new Map<string, Promise<void>>();

export function createApp(config: AppConfig): Server {
  const server = createServer((request, response) => {
    void handleRequest(request, response, config).catch((error: unknown) => {
      if (response.headersSent) {
        response.destroy();
        return;
      }
      const status = error instanceof HttpError ? error.status : 500;
      const message = error instanceof HttpError ? error.message : "Internal server error";
      if (!(error instanceof HttpError)) {
        console.error(error);
      }
      sendJson(response, status, { error: message });
    });
  });
  server.requestTimeout = 0;
  server.headersTimeout = 60_000;
  server.timeout = 0;
  return server;
}

async function handleRequest(request: IncomingMessage, response: ServerResponse, config: AppConfig): Promise<void> {
  const url = new URL(request.url ?? "/", "http://127.0.0.1");
  const path = url.pathname.replace(/\/$/, "") || "/";

  if (request.method === "GET" && path === "/health") {
    sendJson(response, 200, { ok: true });
    return;
  }

  if (path === "/api/upload" && request.method === "OPTIONS") {
    response.writeHead(501, { Allow: "OPTIONS, POST" });
    response.end();
    return;
  }

  const key = authenticate(header(request, "authorization"), config.keys);
  if (!key) {
    sendJson(response, 401, { error: "Unauthorized" });
    return;
  }

  if (request.method === "GET" && path === "/api/session") {
    sendJson(response, 200, { name: key.name });
    return;
  }

  if (request.method === "GET" && path === "/api/uploads") {
    const limit = clampLimit(url.searchParams.get("limit"));
    const offset = clampOffset(url.searchParams.get("offset"));
    const files = await recentFiles(key.directory);
    sendJson(response, 200, {
      items: files.slice(offset, offset + limit).map(describeFile),
      total: files.length,
      offset,
      limit,
    });
    return;
  }

  if (request.method === "POST" && path === "/api/uploads/lookup") {
    await handleLookup(request, response, key);
    return;
  }

  if (request.method === "POST" && path === "/api/upload") {
    await handleUpload(request, response, key);
    return;
  }

  sendJson(response, 404, { error: "Not found" });
}

async function handleLookup(request: IncomingMessage, response: ServerResponse, key: ApiKeyConfig): Promise<void> {
  const body = await readJson(request);
  if (!body || typeof body !== "object" || !Array.isArray((body as { files?: unknown }).files)) {
    throw new HttpError(400, "Expected a files array");
  }
  const files = (body as { files: unknown[] }).files;
  if (files.length > LOOKUP_LIMIT) {
    throw new HttpError(400, `Lookup accepts at most ${LOOKUP_LIMIT} files`);
  }

  const snapshot = await catalogFiles(key.directory, 0);
  const grouped = new Map<string, Set<string>>();

  for (const entry of files) {
    if (!entry || typeof entry !== "object") {
      throw new HttpError(400, "Each lookup file must be an object");
    }
    const record = entry as Record<string, unknown>;
    const assetId = requiredText(record.assetId, "assetId");
    const resourceType = requiredText(record.resourceType, "resourceType");
    if (!isResourceType(resourceType)) {
      throw new HttpError(400, "resourceType must be photo, pairedVideo, or video");
    }
    const filename = typeof record.filename === "string" ? decodeFilename(record.filename) : undefined;
    const relativePath = typeof record.relativePath === "string" ? record.relativePath : "";
    const name = filename || filenameFromPath(relativePath);
    if (!name) {
      throw new HttpError(400, "Each lookup file needs a filename or relativePath");
    }
    const existing = findExisting(snapshot, name, relativePath);
    if (!existing) {
      continue;
    }
    const resources = grouped.get(assetId) ?? new Set<string>();
    resources.add(resourceType);
    grouped.set(assetId, resources);
  }

  sendJson(response, 200, {
    uploaded: [...grouped.entries()].map(([assetId, resources]) => ({
      assetId,
      resources: [...resources],
    })),
  });
}

async function handleUpload(request: IncomingMessage, response: ServerResponse, key: ApiKeyConfig): Promise<void> {
  const assetId = header(request, "x-asset-id");
  const resourceType = header(request, "x-resource-type");
  const filenameHeader = header(request, "x-filename");
  const createdAt = header(request, "x-created-at");
  if (!assetId || !resourceType || !filenameHeader) {
    throw new HttpError(400, "X-Asset-Id, X-Resource-Type, and X-Filename are required");
  }
  if (!isResourceType(resourceType)) {
    throw new HttpError(400, "X-Resource-Type must be photo, pairedVideo, or video");
  }

  const filename = decodeFilename(filenameHeader);
  const relativePath = relativeStoragePath(filename, createdAt);
  const destination = resolveInside(key.directory, relativePath);
  if (!destination) {
    throw new HttpError(400, "Invalid filename");
  }

  await withDirectoryLock(key.directory, async () => {
    const snapshot = await catalogFiles(key.directory, 0);
    const existing = findExisting(snapshot, filename, relativePath);
    if (existing && (await nonEmpty(existing.fullPath))) {
      sendJson(
        response,
        200,
        { relativePath: existing.relativePath, created: false },
        { "X-Relative-Path": existing.relativePath, "X-Asset-Id": assetId },
      );
      drain(request);
      return;
    }

    const incoming = join(key.directory, ".incoming");
    await mkdir(incoming, { recursive: true });
    await mkdir(join(destination, ".."), { recursive: true });
    const temporary = join(incoming, randomUUID());
    try {
      await pipeline(request, createWriteStream(temporary));
      const info = await stat(temporary);
      if (info.size <= 0) {
        throw new HttpError(400, "Upload body is empty");
      }
      await rename(temporary, destination);
      const stored: StoredFile = {
        filename,
        relativePath,
        fullPath: destination,
        bytes: info.size,
        modifiedAt: new Date(),
      };
      invalidateCatalog(key.directory);
      rememberFile(key.directory, stored);
      const contentType = mediaType(header(request, "content-type"), filename);
      sendJson(
        response,
        201,
        { relativePath, created: true, bytes: info.size, contentType },
        { "X-Relative-Path": relativePath, "X-Asset-Id": assetId },
      );
    } catch (error) {
      await rm(temporary, { force: true });
      throw error;
    }
  });
}

function describeFile(file: StoredFile) {
  return {
    filename: file.filename,
    relativePath: file.relativePath,
    bytes: file.bytes,
    contentType: mediaType(undefined, file.filename),
    createdAt: createdAtFromPath(file.relativePath),
    uploadedAt: file.modifiedAt.toISOString(),
  };
}

function createdAtFromPath(relativePath: string): string | null {
  const match = /^(\d{4})\/(\d{2})\//.exec(relativePath);
  if (!match) {
    return null;
  }
  return `${match[1]}-${match[2]}-01T00:00:00.000Z`;
}

function mediaType(headerValue: string | undefined, filename: string): string {
  if (headerValue && !headerValue.startsWith("application/octet-stream")) {
    return headerValue.split(";")[0]?.trim() || guessContentType(filename);
  }
  return guessContentType(filename);
}

function guessContentType(filename: string): string {
  switch (extname(filename).toLowerCase()) {
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".heic":
    case ".heif":
      return "image/heic";
    case ".png":
      return "image/png";
    case ".mov":
      return "video/quicktime";
    case ".mp4":
      return "video/mp4";
    default:
      return "application/octet-stream";
  }
}

function filenameFromPath(relativePath: string): string | undefined {
  const name = relativePath.split(/[/\\]/).pop();
  if (!name) {
    return undefined;
  }
  return decodeFilename(name);
}

function requiredText(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new HttpError(400, `${field} is required`);
  }
  return value.trim();
}

function clampLimit(value: string | null): number {
  const parsed = Number(value ?? "40");
  if (!Number.isInteger(parsed) || parsed < 1) {
    return 40;
  }
  return Math.min(parsed, 100);
}

function clampOffset(value: string | null): number {
  const parsed = Number(value ?? "0");
  if (!Number.isInteger(parsed) || parsed < 0) {
    return 0;
  }
  return parsed;
}

function header(request: IncomingMessage, name: string): string | undefined {
  const value = request.headers[name];
  if (Array.isArray(value)) {
    return value[0];
  }
  return value;
}

function sendJson(
  response: ServerResponse,
  status: number,
  body: unknown,
  extraHeaders: Record<string, string> = {},
): void {
  const payload = JSON.stringify(body);
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(payload),
    ...extraHeaders,
  });
  response.end(payload);
}

async function readJson(request: IncomingMessage): Promise<unknown> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += buffer.length;
    if (size > BODY_LIMIT) {
      throw new HttpError(413, "Request body is too large");
    }
    chunks.push(buffer);
  }
  if (chunks.length === 0) {
    throw new HttpError(400, "Expected a JSON body");
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw new HttpError(400, "Expected JSON");
  }
}

function drain(request: IncomingMessage): void {
  request.resume();
}

async function nonEmpty(fullPath: string): Promise<boolean> {
  try {
    const info = await stat(fullPath);
    return info.isFile() && info.size > 0;
  } catch {
    return false;
  }
}

function withDirectoryLock<T>(directory: string, work: () => Promise<T>): Promise<T> {
  const previous = directoryLocks.get(directory) ?? Promise.resolve();
  const run = previous.then(work, work);
  directoryLocks.set(
    directory,
    run.then(
      () => undefined,
      () => undefined,
    ),
  );
  return run;
}
