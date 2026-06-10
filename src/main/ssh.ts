import { Client, ConnectConfig } from 'ssh2';
import { existsSync, readdirSync, statSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { basename, join, posix, sep } from 'node:path';
import { createServer, Server } from 'node:net';
import type { ConnectionProfile, ConnectionSecret } from '../shared/types';

export type SshExecResult = {
  code: number;
  stdout: string;
  stderr: string;
};

const activeTunnels = new Map<string, { client: Client; server: Server; localPort: number }>();

function connectConfig(profile: ConnectionProfile, secret?: ConnectionSecret): ConnectConfig {
  return {
    host: profile.host,
    port: profile.port,
    username: profile.username,
    password: secret?.password,
    privateKey: secret?.privateKey,
    readyTimeout: 15_000,
    keepaliveInterval: 15_000
  };
}

export function connectSsh(profile: ConnectionProfile, secret?: ConnectionSecret): Promise<Client> {
  return new Promise((resolve, reject) => {
    const client = new Client();
    client
      .on('ready', () => resolve(client))
      .on('error', reject)
      .connect(connectConfig(profile, secret));
  });
}

export async function execSsh(profile: ConnectionProfile, secret: ConnectionSecret | undefined, command: string): Promise<SshExecResult> {
  const client = await connectSsh(profile, secret);
  try {
    return await new Promise((resolve, reject) => {
      client.exec(command, (error, channel) => {
        if (error) {
          reject(error);
          return;
        }

        let stdout = '';
        let stderr = '';
        channel.on('data', (chunk: Buffer) => {
          stdout += chunk.toString();
        });
        channel.stderr.on('data', (chunk: Buffer) => {
          stderr += chunk.toString();
        });
        channel.on('close', (code: number) => {
          resolve({ code, stdout, stderr });
        });
      });
    });
  } finally {
    client.end();
  }
}

function toRemotePath(root: string, localRoot: string, localPath: string): string {
  const relative = localPath.replace(localRoot, '').split(sep).filter(Boolean).join('/');
  return relative ? posix.join(root, relative) : root;
}

async function sftpMkdir(client: Client, remotePath: string): Promise<void> {
  const parts = remotePath.split('/').filter(Boolean);
  let current = '';
  const sftp = await new Promise<import('ssh2').SFTPWrapper>((resolve, reject) => {
    client.sftp((error, wrapper) => (error ? reject(error) : resolve(wrapper)));
  });

  try {
    for (const part of parts) {
      current += `/${part}`;
      await new Promise<void>((resolve) => {
        sftp.mkdir(current, () => resolve());
      });
    }
  } finally {
    sftp.end();
  }
}

async function sftpUploadFile(client: Client, localFile: string, remoteFile: string): Promise<void> {
  const sftp = await new Promise<import('ssh2').SFTPWrapper>((resolve, reject) => {
    client.sftp((error, wrapper) => (error ? reject(error) : resolve(wrapper)));
  });

  try {
    await new Promise<void>((resolve, reject) => {
      sftp.fastPut(localFile, remoteFile, (error) => (error ? reject(error) : resolve()));
    });
  } finally {
    sftp.end();
  }
}

async function sftpDownloadFile(client: Client, remoteFile: string, localFile: string): Promise<void> {
  const sftp = await new Promise<import('ssh2').SFTPWrapper>((resolve, reject) => {
    client.sftp((error, wrapper) => (error ? reject(error) : resolve(wrapper)));
  });

  try {
    await new Promise<void>((resolve, reject) => {
      sftp.fastGet(remoteFile, localFile, (error) => (error ? reject(error) : resolve()));
    });
  } finally {
    sftp.end();
  }
}

export async function uploadFile(profile: ConnectionProfile, secret: ConnectionSecret | undefined, localFile: string, remoteFile: string): Promise<void> {
  if (!existsSync(localFile)) {
    throw new Error(`Local file missing: ${localFile}`);
  }

  const client = await connectSsh(profile, secret);
  try {
    await sftpMkdir(client, posix.dirname(remoteFile));
    await sftpUploadFile(client, localFile, remoteFile);
  } finally {
    client.end();
  }
}

export async function downloadFile(profile: ConnectionProfile, secret: ConnectionSecret | undefined, remoteFile: string, localFile: string): Promise<void> {
  const client = await connectSsh(profile, secret);
  try {
    await sftpDownloadFile(client, remoteFile, localFile);
  } finally {
    client.end();
  }
}

export async function uploadDirectory(profile: ConnectionProfile, secret: ConnectionSecret | undefined, localRoot: string, remoteRoot: string): Promise<void> {
  if (!existsSync(localRoot)) {
    throw new Error(`Payload directory missing: ${localRoot}`);
  }

  const client = await connectSsh(profile, secret);
  try {
    await sftpMkdir(client, remoteRoot);
    const stack = [localRoot];
    while (stack.length > 0) {
      const current = stack.pop()!;
      for (const entry of readdirSync(current)) {
        const localPath = join(current, entry);
        const remotePath = toRemotePath(remoteRoot, localRoot, localPath);
        const stat = statSync(localPath);
        if (stat.isDirectory()) {
          await sftpMkdir(client, remotePath);
          stack.push(localPath);
        } else if (stat.isFile()) {
          await sftpMkdir(client, posix.dirname(remotePath));
          await sftpUploadFile(client, localPath, remotePath);
        }
      }
    }
  } finally {
    client.end();
  }
}

export async function openAgentTunnel(profile: ConnectionProfile, secret: ConnectionSecret | undefined): Promise<number> {
  const existing = activeTunnels.get(profile.id);
  if (existing) return existing.localPort;

  const client = await connectSsh(profile, secret);
  const server = createServer((socket) => {
    socket.on('error', () => undefined);
    client.forwardOut(
      socket.remoteAddress ?? '127.0.0.1',
      socket.remotePort ?? 0,
      '127.0.0.1',
      profile.agentPort,
      (error, stream) => {
        if (error) {
          if (!socket.destroyed) {
            socket.end(
              [
                'HTTP/1.1 502 Bad Gateway',
                'Content-Type: text/plain; charset=utf-8',
                '',
                `Homelab agent is not listening on Proxmox localhost:${profile.agentPort}. Bootstrap or restart the agent, then open the tunnel again.`
              ].join('\r\n')
            );
          }
          return;
        }
        stream.on('error', () => {
          socket.destroy();
        });
        socket.pipe(stream);
        stream.pipe(socket);
      }
    );
  });

  const localPort = await new Promise<number>((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => {
      const address = server.address();
      if (typeof address === 'object' && address) resolve(address.port);
      else reject(new Error('Could not allocate local tunnel port.'));
    });
  });

  client.on('close', () => {
    activeTunnels.delete(profile.id);
    server.close();
  });

  activeTunnels.set(profile.id, { client, server, localPort });
  return localPort;
}

export async function readTextFile(path: string): Promise<string> {
  return readFile(path, 'utf8');
}

export function payloadRoot(appRoot: string, resourceRoot: string, isPackaged: boolean): string {
  return isPackaged ? join(resourceRoot, 'agent') : join(appRoot, 'agent');
}
