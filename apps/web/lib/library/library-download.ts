import { createRequire } from 'node:module';
import { PassThrough, Readable } from 'node:stream';
import type { LibraryDownloadEntry } from '@teya/contracts';
import type { Archiver } from 'archiver';

const MAX_ZIP_BYTES = 100 * 1024 * 1024;
const createArchive = createRequire(import.meta.url)('archiver') as (
  format: string,
  options: { zlib: { level: number } },
) => Archiver;

export class LibraryDownloadBuilder {
  async file(entry: LibraryDownloadEntry): Promise<Response> {
    const body = await this.read(entry);
    return new Response(Uint8Array.from(body).buffer, {
      headers: {
        'Content-Disposition': `attachment; filename*=UTF-8''${encodeURIComponent(entry.name)}`,
        'Content-Length': String(body.byteLength),
        'Content-Type': entry.contentType,
      },
    });
  }

  zip(entries: LibraryDownloadEntry[]): Response {
    const totalSize = entries.reduce((total, entry) => total + entry.size, 0);
    if (totalSize > MAX_ZIP_BYTES) {
      throw new Error('The selected files exceed the 100 MB ZIP limit');
    }
    const output = new PassThrough();
    const archive = createArchive('zip', { zlib: { level: 6 } });
    archive.on('error', (error: Error) => output.destroy(error));
    archive.pipe(output);
    void this.appendAll(archive, entries);
    return new Response(Readable.toWeb(output) as ReadableStream, {
      headers: {
        'Content-Disposition': 'attachment; filename="teya-library.zip"',
        'Content-Type': 'application/zip',
      },
    });
  }

  private async appendAll(
    archive: Archiver,
    entries: LibraryDownloadEntry[],
  ): Promise<void> {
    try {
      for (const entry of entries) {
        archive.append(await this.read(entry), {
          name: this.safePath(entry.path),
        });
      }
      await archive.finalize();
    } catch (error) {
      archive.abort();
      throw error;
    }
  }

  private async read(entry: LibraryDownloadEntry): Promise<Buffer> {
    if (entry.content !== null) {
      return entry.contentType.startsWith('image/')
        ? Buffer.from(entry.content, 'base64')
        : Buffer.from(entry.content);
    }
    if (!entry.url) {
      throw new Error(`File ${entry.name} is unavailable`);
    }
    const response = await fetch(entry.url);
    if (!response.ok) {
      throw new Error(`Unable to download ${entry.name}`);
    }
    return Buffer.from(await response.arrayBuffer());
  }

  private safePath(path: string): string {
    return path
      .split('/')
      .filter((segment) => segment && segment !== '.' && segment !== '..')
      .join('/');
  }
}
