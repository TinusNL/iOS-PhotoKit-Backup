import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { invalidateCatalog } from "../src/catalog.ts";
import { parseConfig } from "../src/config.ts";
import { relativeStoragePath, sanitizeFilename, yearMonth } from "../src/filenames.ts";
import { createApp } from "../src/server.ts";

test("capture date keeps the local calendar month from the timestamp", () => {
  assert.deepEqual(yearMonth("2024-01-01T00:30:00-05:00"), { year: "2024", month: "01" });
  assert.deepEqual(yearMonth("2026-10-20T23:30:00+02:00"), { year: "2026", month: "10" });
  assert.equal(relativeStoragePath("IMG_2456.HEIC", "2026-10-20T23:30:00+02:00"), "2026/10/IMG_2456.HEIC");
});

test("filenames cannot escape the photo directory", () => {
  assert.equal(sanitizeFilename("../../secret.HEIC"), "secret.HEIC");
  assert.equal(sanitizeFilename(".."), "upload.bin");
});

test("config rejects a relative directory and a duplicate key", () => {
  assert.throws(() => parseConfig({ keys: [{ name: "a", apiKey: "k", directory: "photos" }] }), /absolute/);
  const directory = process.cwd();
  assert.throws(
    () =>
      parseConfig({
        keys: [
          { name: "a", apiKey: "same", directory },
          { name: "b", apiKey: "same", directory },
        ],
      }),
    /Duplicate apiKey/,
  );
});

test("existing files are kept and new files land in YYYY/MM", async () => {
  const directory = await mkdtemp(join(tmpdir(), "photokit-backup-"));
  try {
    await mkdir(join(directory, "2019/03"), { recursive: true });
    await mkdir(join(directory, "imports"), { recursive: true });
    await writeFile(join(directory, "2019/03/IMG_2456.HEIC"), "original-heic");
    await writeFile(join(directory, "imports/IMG_2456.MOV"), "original-mov");
    const { baseUrl, close } = await listen(directory);

    const skipped = await upload(baseUrl, {
      assetId: "asset-photo",
      resourceType: "photo",
      filename: "IMG_2456.HEIC",
      createdAt: "2026-10-20T12:00:00+02:00",
      body: "should-not-replace",
    });
    assert.equal(skipped.status, 200);
    assert.equal(skipped.json.relativePath, "2019/03/IMG_2456.HEIC");
    assert.equal(skipped.json.created, false);
    assert.equal(await readFile(join(directory, "2019/03/IMG_2456.HEIC"), "utf8"), "original-heic");
    await assert.rejects(readFile(join(directory, "2026/10/IMG_2456.HEIC")));

    const skippedMovie = await upload(baseUrl, {
      assetId: "asset-photo",
      resourceType: "pairedVideo",
      filename: "IMG_2456.MOV",
      createdAt: "2026-10-20T12:00:00+02:00",
      body: "should-not-replace-mov",
    });
    assert.equal(skippedMovie.status, 200);
    assert.equal(skippedMovie.json.relativePath, "imports/IMG_2456.MOV");
    assert.equal(await readFile(join(directory, "imports/IMG_2456.MOV"), "utf8"), "original-mov");

    const created = await upload(baseUrl, {
      assetId: "asset-new",
      resourceType: "photo",
      filename: "IMG_3000.HEIC",
      createdAt: "2026-10-20T12:00:00+02:00",
      body: "new-photo",
    });
    assert.equal(created.status, 201);
    assert.equal(created.json.relativePath, "2026/10/IMG_3000.HEIC");
    assert.equal(await readFile(join(directory, "2026/10/IMG_3000.HEIC"), "utf8"), "new-photo");

    const again = await upload(baseUrl, {
      assetId: "asset-new",
      resourceType: "photo",
      filename: "IMG_3000.HEIC",
      createdAt: "2026-10-20T12:00:00+02:00",
      body: "replacement",
    });
    assert.equal(again.status, 200);
    assert.equal(await readFile(join(directory, "2026/10/IMG_3000.HEIC"), "utf8"), "new-photo");

    const lookup = await fetch(`${baseUrl}/api/uploads/lookup`, {
      method: "POST",
      headers: { Authorization: "Bearer test-key", "Content-Type": "application/json" },
      body: JSON.stringify({
        files: [
          {
            assetId: "asset-photo",
            resourceType: "photo",
            filename: "IMG_2456.HEIC",
            relativePath: "2026/10/IMG_2456.HEIC",
          },
          {
            assetId: "asset-photo",
            resourceType: "pairedVideo",
            filename: "IMG_2456.MOV",
            relativePath: "2026/10/IMG_2456.MOV",
          },
          {
            assetId: "missing",
            resourceType: "video",
            filename: "IMG_9999.MOV",
            relativePath: "2026/10/IMG_9999.MOV",
          },
        ],
      }),
    });
    const lookupJson = (await lookup.json()) as {
      uploaded: Array<{ assetId: string; resources: string[] }>;
    };
    const photo = lookupJson.uploaded.find((item) => item.assetId === "asset-photo");
    assert.ok(photo);
    assert.deepEqual(photo.resources.sort(), ["pairedVideo", "photo"]);
    assert.equal(
      lookupJson.uploaded.find((item) => item.assetId === "missing"),
      undefined,
    );

    await mkdir(join(directory, "2026/10/@eaDir/IMG_3000.HEIC"), { recursive: true });
    await mkdir(join(directory, "2026/99"), { recursive: true });
    await writeFile(join(directory, "2026/10/@eaDir/IMG_3000.HEIC/SYNOPHOTO_THUMB_M.jpg"), "thumb");
    await writeFile(join(directory, "2026/10/@eaDir/IMG_3000.HEIC/SYNOINDEX_MEDIA_INFO"), "index");
    await writeFile(join(directory, "2026/99/NOPE.jpg"), "nope");
    await writeFile(join(directory, "loose.jpg"), "loose");
    invalidateCatalog(directory);

    const recent = (await (await fetch(`${baseUrl}/api/uploads?limit=10`, {
      headers: { Authorization: "Bearer test-key" },
    })).json()) as { items: Array<{ filename: string }>; total: number };
    assert.equal(recent.total, 2);
    assert.deepEqual(
      recent.items.map((item) => item.filename).sort(),
      ["IMG_2456.HEIC", "IMG_3000.HEIC"],
    );

    const page = (await (await fetch(`${baseUrl}/api/uploads?limit=1&offset=1`, {
      headers: { Authorization: "Bearer test-key" },
    })).json()) as { items: Array<{ filename: string }>; total: number };
    assert.equal(page.total, 2);
    assert.deepEqual(page.items.map((item) => item.filename), ["IMG_2456.HEIC"]);

    const options = await fetch(`${baseUrl}/api/upload`, { method: "OPTIONS" });
    assert.equal(options.status, 501);

    const denied = await fetch(`${baseUrl}/api/session`, { headers: { Authorization: "Bearer nope" } });
    assert.equal(denied.status, 401);

    const session = (await (await fetch(`${baseUrl}/api/session`, {
      headers: { Authorization: "Bearer test-key" },
    })).json()) as { name: string };
    assert.equal(session.name, "test");

    await close();
  } finally {
    invalidateCatalog(directory);
    await rm(directory, { recursive: true, force: true });
  }
});

async function listen(directory: string): Promise<{ baseUrl: string; close: () => Promise<void> }> {
  const server = createApp({
    port: 0,
    keys: [{ name: "test", apiKey: "test-key", directory }],
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  const address = server.address();
  if (!address || typeof address === "string") {
    throw new Error("No port");
  }
  return {
    baseUrl: `http://127.0.0.1:${address.port}`,
    close: () => new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve()))),
  };
}

async function upload(
  baseUrl: string,
  input: { assetId: string; resourceType: string; filename: string; createdAt: string; body: string },
): Promise<{ status: number; json: { relativePath: string; created: boolean } }> {
  const response = await fetch(`${baseUrl}/api/upload`, {
    method: "POST",
    headers: {
      Authorization: "Bearer test-key",
      "X-Asset-Id": input.assetId,
      "X-Resource-Type": input.resourceType,
      "X-Filename": encodeURIComponent(input.filename),
      "X-Created-At": input.createdAt,
      "Content-Type": input.filename.endsWith(".MOV") ? "video/quicktime" : "image/heic",
    },
    body: input.body,
  });
  return {
    status: response.status,
    json: (await response.json()) as { relativePath: string; created: boolean },
  };
}
