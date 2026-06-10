import { app, safeStorage } from 'electron';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';

type StoreShape = Record<string, unknown>;
type KeytarCredential = {
  account: string;
  password: string;
};

type KeytarApi = {
  getPassword: (service: string, account: string) => Promise<string | null>;
  setPassword: (service: string, account: string, password: string) => Promise<void>;
  deletePassword: (service: string, account: string) => Promise<boolean>;
  findCredentials: (service: string) => Promise<KeytarCredential[]>;
};

const CREDENTIAL_SERVICE = 'com.bacmaster.homelabv4';

const storePath = () => join(app.getPath('userData'), 'secure-store.bin');

async function ensureParent(path: string): Promise<void> {
  await mkdir(dirname(path), { recursive: true });
}

function normalizeKeytar(module: unknown): KeytarApi | null {
  const candidates = [module, (module as { default?: unknown })?.default];
  for (const candidate of candidates) {
    const api = candidate as Partial<KeytarApi> | undefined;
    if (
      api &&
      typeof api.getPassword === 'function' &&
      typeof api.setPassword === 'function' &&
      typeof api.deletePassword === 'function' &&
      typeof api.findCredentials === 'function'
    ) {
      return api as KeytarApi;
    }
  }
  return null;
}

async function loadKeytar(): Promise<KeytarApi | null> {
  try {
    return normalizeKeytar(await import('keytar'));
  } catch {
    return null;
  }
}

function parseValue<T>(raw: string | null): T | null {
  if (!raw) return null;
  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

async function readSafeStorageStore(): Promise<StoreShape> {
  const file = storePath();
  if (!existsSync(file)) return {};

  const raw = await readFile(file);
  if (raw.length === 0) return {};

  try {
    const decrypted = safeStorage.decryptString(raw);
    return JSON.parse(decrypted) as StoreShape;
  } catch {
    return {};
  }
}

async function writeSafeStorageStore(data: StoreShape): Promise<void> {
  const file = storePath();
  await ensureParent(file);
  const encrypted = safeStorage.encryptString(JSON.stringify(data, null, 2));
  await writeFile(file, encrypted, { mode: 0o600 });
}

export async function readSecureStore(): Promise<StoreShape> {
  const keytar = await loadKeytar();
  if (keytar) {
    const credentials = await keytar.findCredentials(CREDENTIAL_SERVICE);
    if (credentials.length > 0) {
      return credentials.reduce<StoreShape>((acc, item) => {
        const parsed = parseValue<unknown>(item.password);
        if (parsed !== null) acc[item.account] = parsed;
        return acc;
      }, {});
    }
  }

  return readSafeStorageStore();
}

export async function writeSecureStore(data: StoreShape): Promise<void> {
  const keytar = await loadKeytar();
  if (keytar) {
    const existing = await keytar.findCredentials(CREDENTIAL_SERVICE);
    await Promise.all(
      existing
        .filter((item) => !(item.account in data))
        .map((item) => keytar.deletePassword(CREDENTIAL_SERVICE, item.account))
    );
    await Promise.all(
      Object.entries(data).map(([key, value]) => keytar.setPassword(CREDENTIAL_SERVICE, key, JSON.stringify(value)))
    );
    return;
  }

  await writeSafeStorageStore(data);
}

export async function setSecureValue<T>(key: string, value: T): Promise<void> {
  const keytar = await loadKeytar();
  if (keytar) {
    await keytar.setPassword(CREDENTIAL_SERVICE, key, JSON.stringify(value));
    return;
  }

  const data = await readSecureStore();
  data[key] = value;
  await writeSecureStore(data);
}

export async function getSecureValue<T>(key: string): Promise<T | null> {
  const keytar = await loadKeytar();
  if (keytar) {
    const value = parseValue<T>(await keytar.getPassword(CREDENTIAL_SERVICE, key));
    if (value !== null) return value;
  }

  const data = await readSecureStore();
  return (data[key] as T | undefined) ?? null;
}
