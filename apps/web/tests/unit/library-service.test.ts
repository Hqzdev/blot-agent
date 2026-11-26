import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import type { LibraryCreateUploadInput } from '@teya/contracts';
import {
  ConversationForbiddenError,
  ConversationValidationError,
  type LibraryDownloadRecord,
  type LibraryItemRecord,
  type LibraryRepository,
  LibraryService,
} from '@teya/service-conversation';

const ownerId = '00000000-0000-4000-8000-000000000001';
const otherOwnerId = '00000000-0000-4000-8000-000000000002';

class LibraryRepositoryFake implements LibraryRepository {
  readonly items = new Map<string, LibraryItemRecord>();
  private nextId = 1;

  createLibraryFolder(input: {
    name: string;
    ownerId: string;
    parentId: string | null;
  }): Promise<LibraryItemRecord> {
    return Promise.resolve(
      this.add({
        itemType: 'folder',
        name: input.name,
        ownerId: input.ownerId,
        parentId: input.parentId,
        source: 'created',
      }),
    );
  }

  createLibraryUpload(
    input: LibraryCreateUploadInput & {
      ownerId: string;
      parentId: string | null;
    },
  ): Promise<LibraryItemRecord> {
    return Promise.resolve(
      this.add({
        contentType: input.contentType,
        itemType: 'file',
        name: input.name,
        ownerId: input.ownerId,
        parentId: input.parentId,
        size: input.size,
        source: 'uploaded',
        url: input.url,
      }),
    );
  }

  deleteLibraryItems(ids: string[]): Promise<string[]> {
    for (const id of ids) {
      this.items.delete(id);
    }
    return Promise.resolve([]);
  }

  findExpiredLibraryRootIds(now: Date): Promise<string[]> {
    return Promise.resolve(
      [...this.items.values()]
        .filter(
          (item) =>
            item.deletionRootId === item.id &&
            item.purgeAfter &&
            item.purgeAfter <= now,
        )
        .map((item) => item.id),
    );
  }

  findLibraryDownloadRecords(ids: string[]): Promise<LibraryDownloadRecord[]> {
    return Promise.resolve(
      ids.flatMap((id) => {
        const item = this.items.get(id);
        return item
          ? [
              {
                ...item,
                content: item.documentId ? 'artifact content' : null,
                pathname: item.objectFileId ? `${item.id}.bin` : null,
              },
            ]
          : [];
      }),
    );
  }

  findLibraryItem(id: string): Promise<LibraryItemRecord | undefined> {
    return Promise.resolve(this.items.get(id));
  }

  findLibraryItems(owner: string): Promise<LibraryItemRecord[]> {
    return Promise.resolve(
      [...this.items.values()].filter((item) => item.ownerId === owner),
    );
  }

  isLibraryDocumentAvailable(
    actorId: string,
    documentId: string,
  ): Promise<boolean> {
    return Promise.resolve(
      [...this.items.values()].some(
        (item) =>
          item.ownerId === actorId &&
          item.documentId === documentId &&
          !item.deletedAt,
      ),
    );
  }

  restoreLibraryItems(rootIds: string[]): Promise<void> {
    const roots = new Set(rootIds);
    for (const [id, item] of this.items) {
      if (item.deletionRootId && roots.has(item.deletionRootId)) {
        this.items.set(id, {
          ...item,
          deletedAt: null,
          deletionRootId: null,
          purgeAfter: null,
        });
      }
    }
    return Promise.resolve();
  }

  trashLibraryItems(
    groups: Array<{ ids: string[]; rootId: string }>,
    deletedAt: Date,
    purgeAfter: Date,
  ): Promise<void> {
    for (const group of groups) {
      for (const id of group.ids) {
        const item = this.items.get(id);
        if (item) {
          this.items.set(id, {
            ...item,
            deletedAt,
            deletionRootId: group.rootId,
            purgeAfter,
          });
        }
      }
    }
    return Promise.resolve();
  }

  updateLibraryItem(
    id: string,
    input: { name?: string; parentId?: string | null },
  ): Promise<LibraryItemRecord> {
    const item = this.items.get(id);
    if (!item) {
      throw new Error('Missing fake Library item');
    }
    const updated = {
      ...item,
      name: input.name ?? item.name,
      parentId: input.parentId === undefined ? item.parentId : input.parentId,
      updatedAt: new Date(),
    };
    this.items.set(id, updated);
    return Promise.resolve(updated);
  }

  add(
    input: Partial<LibraryItemRecord> &
      Pick<LibraryItemRecord, 'itemType' | 'name' | 'ownerId' | 'source'>,
  ): LibraryItemRecord {
    const id = `00000000-0000-4000-8000-${String(this.nextId++).padStart(12, '0')}`;
    const item: LibraryItemRecord = {
      contentType: null,
      createdAt: new Date(),
      deletedAt: null,
      deletionRootId: null,
      documentId: null,
      id,
      objectFileId: null,
      parentId: null,
      purgeAfter: null,
      size: 0,
      updatedAt: new Date(),
      url: null,
      ...input,
    };
    this.items.set(id, item);
    return item;
  }
}

test('Library list keeps folders first and paginates filtered results', async () => {
  const repository = new LibraryRepositoryFake();
  const service = new LibraryService(repository);
  repository.add({
    contentType: 'image/png',
    itemType: 'file',
    name: 'Beta.png',
    ownerId,
    size: 40,
    source: 'generated',
  });
  repository.add({
    itemType: 'folder',
    name: 'Assets',
    ownerId,
    source: 'created',
  });
  repository.add({
    contentType: 'text/plain',
    itemType: 'file',
    name: 'Alpha.txt',
    ownerId,
    size: 20,
    source: 'uploaded',
  });

  const first = await service.list(ownerId, {
    deleted: false,
    direction: 'asc',
    limit: 2,
    sort: 'name',
    tab: 'all',
  });
  assert.deepEqual(
    first.items.map((item) => item.name),
    ['Assets', 'Alpha.txt'],
  );
  assert.ok(first.nextCursor);

  const second = await service.list(ownerId, {
    cursor: first.nextCursor ?? undefined,
    deleted: false,
    direction: 'asc',
    limit: 2,
    sort: 'name',
    tab: 'all',
  });
  assert.deepEqual(
    second.items.map((item) => item.name),
    ['Beta.png'],
  );

  const images = await service.list(ownerId, {
    deleted: false,
    direction: 'desc',
    limit: 10,
    sort: 'modified',
    tab: 'images',
  });
  assert.deepEqual(
    images.items.map((item) => item.name),
    ['Beta.png'],
  );
});

test('Library rejects cross-user destinations and folder cycles', async () => {
  const repository = new LibraryRepositoryFake();
  const service = new LibraryService(repository);
  const ownFolder = repository.add({
    itemType: 'folder',
    name: 'Own',
    ownerId,
    source: 'created',
  });
  const childFolder = repository.add({
    itemType: 'folder',
    name: 'Child',
    ownerId,
    parentId: ownFolder.id,
    source: 'created',
  });
  const foreignFolder = repository.add({
    itemType: 'folder',
    name: 'Foreign',
    ownerId: otherOwnerId,
    source: 'created',
  });

  await assert.rejects(
    service.createFolder(ownerId, {
      name: 'Blocked',
      parentId: foreignFolder.id,
    }),
    ConversationForbiddenError,
  );
  await assert.rejects(
    service.update(ownerId, ownFolder.id, { parentId: childFolder.id }),
    ConversationValidationError,
  );
});

test('restoring a folder does not restore an independently deleted child', async () => {
  const repository = new LibraryRepositoryFake();
  const service = new LibraryService(repository);
  const folder = repository.add({
    itemType: 'folder',
    name: 'Folder',
    ownerId,
    source: 'created',
  });
  const child = repository.add({
    itemType: 'file',
    name: 'Child.txt',
    ownerId,
    parentId: folder.id,
    source: 'uploaded',
  });

  await service.trash(ownerId, [child.id]);
  await service.trash(ownerId, [folder.id]);
  await service.restore(ownerId, [folder.id]);

  assert.equal(repository.items.get(folder.id)?.deletedAt, null);
  assert.ok(repository.items.get(child.id)?.deletedAt);
  assert.equal(repository.items.get(child.id)?.deletionRootId, child.id);
});

test('Library migration backfills stored files and generated artifacts', async () => {
  const sql = await readFile(
    new URL(
      '../../packages/database/migrations/0003_library.sql',
      import.meta.url,
    ),
    'utf8',
  );
  assert.match(sql, /INSERT INTO "conversation"\."library_items"/);
  assert.match(sql, /FROM "conversation"\."object_files"/);
  assert.match(sql, /FROM "conversation"\."documents"/);
  assert.match(sql, /ON CONFLICT \("document_id"\)/);
});
