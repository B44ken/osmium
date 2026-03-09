import { constants } from "node:fs";
import { access, mkdir, rm } from "node:fs/promises";
import net from "node:net";
import os from "node:os";
import path from "node:path";

import type { AppCommand } from "./protocol.ts";

export function osmDir(): string {
  return path.join(os.homedir(), ".osm");
}

export function socketPath(): string {
  return path.join(osmDir(), "osmium.sock");
}

export async function ensureOsmDir(): Promise<void> {
  await mkdir(osmDir(), { recursive: true });
}

export async function sendCommand(command: AppCommand): Promise<boolean> {
  const target = socketPath();

  return await new Promise((resolve, reject) => {
    const client = net.createConnection(target);

    client.once("connect", () => {
      client.end(`${JSON.stringify(command)}\n`);
      resolve(true);
    });

    client.once("error", async (error: NodeJS.ErrnoException) => {
      client.destroy();
      if (error.code === "ENOENT" || error.code === "ECONNREFUSED") {
        if (error.code === "ECONNREFUSED") {
          await safeRemove(target);
        }
        resolve(false);
        return;
      }
      reject(error);
    });
  });
}

export async function waitForSocket(timeoutMs = 8_000): Promise<void> {
  const started = Date.now();
  const target = socketPath();

  while (Date.now() - started < timeoutMs) {
    if (await exists(target)) {
      try {
        const connected = await sendProbe(target);
        if (connected) {
          return;
        }
      } catch {}
    }
    await Bun.sleep(60);
  }

  throw new Error(`Timed out waiting for ${target}`);
}

async function sendProbe(target: string): Promise<boolean> {
  return await new Promise((resolve) => {
    const client = net.createConnection(target);
    client.once("connect", () => {
      client.end();
      resolve(true);
    });
    client.once("error", () => {
      client.destroy();
      resolve(false);
    });
  });
}

async function exists(target: string): Promise<boolean> {
  try {
    await access(target, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

async function safeRemove(target: string): Promise<void> {
  try {
    await rm(target, { force: true });
  } catch {
    // Ignore stale-socket cleanup failures.
  }
}
