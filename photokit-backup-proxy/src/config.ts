import { existsSync, readFileSync, statSync } from "node:fs";
import { isAbsolute, resolve } from "node:path";

export interface ApiKeyConfig {
  name: string;
  apiKey: string;
  directory: string;
}

export interface AppConfig {
  port: number;
  keys: ApiKeyConfig[];
}

export function resolveConfigPath(): string {
  if (process.env.CONFIG_PATH) {
    return process.env.CONFIG_PATH;
  }
  const local = resolve("config.json");
  if (existsSync(local)) {
    return local;
  }
  return "/config/config.json";
}

export function loadConfig(path: string): AppConfig {
  let raw: string;
  try {
    raw = readFileSync(path, "utf8");
  } catch {
    throw new Error(`Cannot read config file at ${path}`);
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error(`Config file at ${path} is not valid JSON`);
  }

  return parseConfig(parsed);
}

export function parseConfig(value: unknown): AppConfig {
  if (!value || typeof value !== "object") {
    throw new Error("Config must be a JSON object");
  }

  const record = value as Record<string, unknown>;
  const port = record.port === undefined ? 8080 : record.port;
  if (typeof port !== "number" || !Number.isInteger(port) || port < 1 || port > 65535) {
    throw new Error("Config port must be an integer from 1 to 65535");
  }

  if (!Array.isArray(record.keys) || record.keys.length === 0) {
    throw new Error("Config keys must be a non-empty array");
  }

  const keys: ApiKeyConfig[] = [];
  const seenKeys = new Set<string>();
  const seenNames = new Set<string>();

  for (const entry of record.keys) {
    if (!entry || typeof entry !== "object") {
      throw new Error("Each config key must be an object");
    }
    const item = entry as Record<string, unknown>;
    const name = requiredString(item.name, "name");
    const apiKey = requiredString(item.apiKey, "apiKey");
    const directory = requiredString(item.directory, "directory");

    if (seenNames.has(name)) {
      throw new Error(`Duplicate config name: ${name}`);
    }
    if (seenKeys.has(apiKey)) {
      throw new Error("Duplicate apiKey in config");
    }
    if (!isAbsolute(directory)) {
      throw new Error(`Directory for ${name} must be an absolute path`);
    }
    if (!existsSync(directory) || !statSync(directory).isDirectory()) {
      throw new Error(`Directory for ${name} does not exist: ${directory}`);
    }

    seenNames.add(name);
    seenKeys.add(apiKey);
    keys.push({ name, apiKey, directory });
  }

  return { port, keys };
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim() === "") {
    throw new Error(`Config field ${field} must be a non-empty string`);
  }
  return value.trim();
}
