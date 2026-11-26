import 'server-only';

import { randomUUID } from 'node:crypto';
import { del, put } from '@vercel/blob';
import { isTestEnvironment } from '../constants';

export interface StoredObject {
  contentType: string;
  pathname: string;
  size: number;
  url: string;
}

export interface ObjectStorage {
  delete(pathnames: string[]): Promise<void>;
  upload(userId: string, file: File): Promise<StoredObject>;
}

export class VercelBlobObjectStorage implements ObjectStorage {
  async delete(pathnames: string[]): Promise<void> {
    if (pathnames.length > 0) {
      await del(pathnames);
    }
  }

  async upload(userId: string, file: File): Promise<StoredObject> {
    const extension = this.getExtension(file.name);
    const pathname = `users/${userId}/${randomUUID()}${extension}`;
    const uploaded = await put(pathname, file, {
      access: 'public',
      addRandomSuffix: false,
      contentType: file.type,
    });
    return {
      contentType: file.type,
      pathname: uploaded.pathname,
      size: file.size,
      url: uploaded.url,
    };
  }

  private getExtension(filename: string): string {
    const match = filename.toLowerCase().match(/\.[a-z0-9]{1,10}$/);
    return match?.[0] ?? '';
  }
}

export class TestObjectStorage implements ObjectStorage {
  async delete(): Promise<void> {}

  async upload(userId: string, file: File): Promise<StoredObject> {
    const extension = file.name.toLowerCase().match(/\.[a-z0-9]{1,10}$/)?.[0];
    const pathname = `tests/${userId}/${randomUUID()}${extension ?? ''}`;
    return {
      contentType: file.type || 'application/octet-stream',
      pathname,
      size: file.size,
      url: `https://storage.test/${pathname}`,
    };
  }
}

let objectStorage: ObjectStorage | undefined;

export function getObjectStorage(): ObjectStorage {
  if (!objectStorage) {
    objectStorage = isTestEnvironment
      ? new TestObjectStorage()
      : new VercelBlobObjectStorage();
  }
  return objectStorage;
}
