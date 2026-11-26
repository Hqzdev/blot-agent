import type {
  LibraryBulkInput,
  LibraryCreateFolderInput,
  LibraryCreateUploadInput,
  LibraryDownloadEntry,
  LibraryFileCategory,
  LibraryItem,
  LibraryListInput,
  LibraryListResult,
  LibraryUpdateItemInput,
} from '@teya/contracts';

import {
  ConversationForbiddenError,
  ConversationNotFoundError,
  ConversationValidationError,
} from './errors';
import type {
  LibraryDownloadRecord,
  LibraryItemRecord,
  LibraryRepository,
} from './repository';

const TRASH_RETENTION_MS = 30 * 24 * 60 * 60 * 1000;

export class LibraryService {
  constructor(private readonly repository: LibraryRepository) {}

  async list(
    actorId: string,
    input: LibraryListInput,
  ): Promise<LibraryListResult> {
    const rows = await this.repository.findLibraryItems(actorId);
    const rowById = new Map(rows.map((row) => [row.id, row]));
    const query = input.query?.trim().toLocaleLowerCase();
    const filtered = rows.filter((row) => {
      if (input.deleted) {
        if (!row.deletedAt || row.deletionRootId !== row.id) {
          return false;
        }
      } else if (row.deletedAt) {
        return false;
      }
      if (!query && (row.parentId ?? null) !== (input.parentId ?? null)) {
        return false;
      }
      if (query && !row.name.toLocaleLowerCase().includes(query)) {
        return false;
      }
      if (row.itemType === 'folder') {
        return !input.source && !input.category && input.tab === 'all';
      }
      if (input.source && row.source !== input.source) {
        return false;
      }
      const category = this.getCategory(row);
      if (input.category && category !== input.category) {
        return false;
      }
      if (input.tab === 'images' && category !== 'image') {
        return false;
      }
      if (input.tab === 'documents' && category === 'image') {
        return false;
      }
      return true;
    });
    const direction = input.direction === 'asc' ? 1 : -1;
    filtered.sort((first, second) => {
      if (first.itemType === 'folder' && second.itemType !== 'folder') {
        return -1;
      }
      if (first.itemType !== 'folder' && second.itemType === 'folder') {
        return 1;
      }
      const comparison =
        input.sort === 'name'
          ? first.name.localeCompare(second.name)
          : input.sort === 'size'
            ? first.size - second.size
            : first.updatedAt.getTime() - second.updatedAt.getTime();
      return comparison === 0
        ? first.id.localeCompare(second.id)
        : comparison * direction;
    });
    const offset = this.decodeCursor(input.cursor);
    const page = filtered.slice(offset, offset + input.limit);
    const nextOffset = offset + page.length;
    return {
      breadcrumbs: input.parentId
        ? this.buildPath(rowById, input.parentId, true)
        : [],
      items: page.map((row) => this.toItem(row, rowById)),
      nextCursor:
        nextOffset < filtered.length ? this.encodeCursor(nextOffset) : null,
    };
  }

  async get(actorId: string, id: string): Promise<LibraryItem> {
    const rows = await this.repository.findLibraryItems(actorId);
    const rowById = new Map(rows.map((row) => [row.id, row]));
    const row = rowById.get(id);
    if (!row) {
      throw new ConversationNotFoundError('Library item not found');
    }
    return this.toItem(row, rowById);
  }

  async createFolder(
    actorId: string,
    input: LibraryCreateFolderInput,
  ): Promise<LibraryItem> {
    await this.requireDestination(actorId, input.parentId ?? null);
    const created = await this.repository.createLibraryFolder({
      name: input.name.trim(),
      ownerId: actorId,
      parentId: input.parentId ?? null,
    });
    return this.toItem(created, new Map([[created.id, created]]));
  }

  async createUpload(
    actorId: string,
    input: LibraryCreateUploadInput,
  ): Promise<LibraryItem> {
    await this.requireDestination(actorId, input.parentId ?? null);
    const created = await this.repository.createLibraryUpload({
      ...input,
      name: input.name.trim(),
      ownerId: actorId,
      parentId: input.parentId ?? null,
    });
    return this.toItem(created, new Map([[created.id, created]]));
  }

  async update(
    actorId: string,
    id: string,
    input: LibraryUpdateItemInput,
  ): Promise<LibraryItem> {
    const rows = await this.repository.findLibraryItems(actorId);
    const rowById = new Map(rows.map((row) => [row.id, row]));
    const item = rowById.get(id);
    if (!item) {
      throw new ConversationNotFoundError('Library item not found');
    }
    if (item.deletedAt) {
      throw new ConversationValidationError(
        'Deleted items must be restored before editing',
      );
    }
    const nextParent =
      input.parentId === undefined ? item.parentId : input.parentId;
    if (input.parentId !== undefined) {
      await this.requireDestination(actorId, nextParent ?? null);
      if (
        item.itemType === 'folder' &&
        nextParent &&
        this.isDescendant(rowById, nextParent, item.id)
      ) {
        throw new ConversationValidationError(
          'A folder cannot be moved into itself',
        );
      }
    }
    const updated = await this.repository.updateLibraryItem(id, {
      name:
        input.name === undefined
          ? undefined
          : this.preserveExtension(item, input.name.trim()),
      parentId: input.parentId,
    });
    const updatedMap = new Map(rowById);
    updatedMap.set(updated.id, updated);
    return this.toItem(updated, updatedMap);
  }

  async trash(actorId: string, ids: string[]): Promise<void> {
    const rows = await this.repository.findLibraryItems(actorId);
    const rowById = new Map(rows.map((row) => [row.id, row]));
    const roots = this.requireRoots(ids, rowById, false);
    const now = new Date();
    const purgeAfter = new Date(now.getTime() + TRASH_RETENTION_MS);
    const groups = roots.map((root) => ({
      ids: this.collectDescendants(rows, root.id)
        .filter((item) => !item.deletedAt)
        .map((item) => item.id),
      rootId: root.id,
    }));
    await this.repository.trashLibraryItems(groups, now, purgeAfter);
  }

  async restore(actorId: string, ids: string[]): Promise<void> {
    const rows = await this.repository.findLibraryItems(actorId);
    const rowById = new Map(rows.map((row) => [row.id, row]));
    const roots = this.requireRoots(ids, rowById, true);
    await this.repository.restoreLibraryItems(roots.map((item) => item.id));
  }

  async permanentlyDelete(actorId: string, ids: string[]): Promise<string[]> {
    const rows = await this.repository.findLibraryItems(actorId);
    const rowById = new Map(rows.map((row) => [row.id, row]));
    const roots = this.requireRoots(ids, rowById, true);
    const affectedIds = [
      ...new Set(
        roots.flatMap((root) =>
          this.collectDescendants(rows, root.id).map((item) => item.id),
        ),
      ),
    ];
    return this.repository.deleteLibraryItems(affectedIds);
  }

  async bulk(actorId: string, input: LibraryBulkInput): Promise<string[]> {
    if (input.action === 'move') {
      await Promise.all(
        input.ids.map((id) =>
          this.update(actorId, id, { parentId: input.parentId ?? null }),
        ),
      );
      return [];
    }
    if (input.action === 'trash') {
      await this.trash(actorId, input.ids);
      return [];
    }
    if (input.action === 'restore') {
      await this.restore(actorId, input.ids);
      return [];
    }
    return this.permanentlyDelete(actorId, input.ids);
  }

  async getDownloadManifest(
    actorId: string,
    ids: string[],
  ): Promise<LibraryDownloadEntry[]> {
    const rows = await this.repository.findLibraryItems(actorId);
    const rowById = new Map(rows.map((row) => [row.id, row]));
    const roots = this.requireRoots(ids, rowById, false);
    const selected = [
      ...new Set(
        roots.flatMap((root) =>
          this.collectDescendants(rows, root.id)
            .filter((item) => !item.deletedAt && item.itemType !== 'folder')
            .map((item) => item.id),
        ),
      ),
    ];
    const records = await this.repository.findLibraryDownloadRecords(selected);
    const recordById = new Map(records.map((record) => [record.id, record]));
    return selected.flatMap((id) => {
      const record = recordById.get(id);
      if (!record) {
        return [];
      }
      return [this.toDownloadEntry(record, rowById, roots)];
    });
  }

  getExpiredRootIds(now: Date): Promise<string[]> {
    return this.repository.findExpiredLibraryRootIds(now);
  }

  isDocumentAvailable(actorId: string, documentId: string): Promise<boolean> {
    return this.repository.isLibraryDocumentAvailable(actorId, documentId);
  }

  private requireRoots(
    ids: string[],
    rowById: Map<string, LibraryItemRecord>,
    deleted: boolean,
  ): LibraryItemRecord[] {
    const items = [...new Set(ids)].map((id) => {
      const item = rowById.get(id);
      if (!item) {
        throw new ConversationNotFoundError('Library item not found');
      }
      if (deleted && (!item.deletedAt || item.deletionRootId !== item.id)) {
        throw new ConversationValidationError(
          'Only deleted root items can be restored or removed permanently',
        );
      }
      if (!deleted && item.deletedAt) {
        throw new ConversationValidationError('Library item is deleted');
      }
      return item;
    });
    const selectedIds = new Set(items.map((item) => item.id));
    return items.filter((item) => {
      let parentId = item.parentId;
      while (parentId) {
        if (selectedIds.has(parentId)) {
          return false;
        }
        parentId = rowById.get(parentId)?.parentId ?? null;
      }
      return true;
    });
  }

  private async requireDestination(
    actorId: string,
    parentId: string | null,
  ): Promise<void> {
    if (!parentId) {
      return;
    }
    const parent = await this.repository.findLibraryItem(parentId);
    if (!parent) {
      throw new ConversationNotFoundError('Destination folder not found');
    }
    if (parent.ownerId !== actorId) {
      throw new ConversationForbiddenError(
        'Destination folder access is forbidden',
      );
    }
    if (parent.itemType !== 'folder' || parent.deletedAt) {
      throw new ConversationValidationError('Destination is not available');
    }
  }

  private collectDescendants(
    rows: LibraryItemRecord[],
    rootId: string,
  ): LibraryItemRecord[] {
    const result: LibraryItemRecord[] = [];
    const queue = [rootId];
    while (queue.length > 0) {
      const currentId = queue.shift();
      if (!currentId) {
        continue;
      }
      const current = rows.find((item) => item.id === currentId);
      if (current) {
        result.push(current);
      }
      queue.push(
        ...rows
          .filter((item) => item.parentId === currentId)
          .map((item) => item.id),
      );
    }
    return result;
  }

  private isDescendant(
    rowById: Map<string, LibraryItemRecord>,
    id: string,
    possibleAncestorId: string,
  ): boolean {
    let currentId: string | null = id;
    while (currentId) {
      if (currentId === possibleAncestorId) {
        return true;
      }
      currentId = rowById.get(currentId)?.parentId ?? null;
    }
    return false;
  }

  private toItem(
    row: LibraryItemRecord,
    rowById: Map<string, LibraryItemRecord>,
  ): LibraryItem {
    return {
      ...row,
      path: this.buildPath(rowById, row.id, false),
    };
  }

  private buildPath(
    rowById: Map<string, LibraryItemRecord>,
    id: string,
    includeSelf: boolean,
  ): Array<{ id: string; name: string }> {
    const path: Array<{ id: string; name: string }> = [];
    let current = includeSelf
      ? rowById.get(id)
      : rowById.get(id)?.parentId
        ? rowById.get(rowById.get(id)?.parentId ?? '')
        : undefined;
    const visited = new Set<string>();
    while (current && !visited.has(current.id)) {
      visited.add(current.id);
      path.unshift({ id: current.id, name: current.name });
      current = current.parentId ? rowById.get(current.parentId) : undefined;
    }
    return path;
  }

  private getCategory(item: LibraryItemRecord): LibraryFileCategory {
    const contentType = item.contentType?.toLocaleLowerCase() ?? '';
    const extension = item.name.split('.').at(-1)?.toLocaleLowerCase() ?? '';
    if (contentType.startsWith('image/')) {
      return 'image';
    }
    if (contentType === 'application/pdf' || extension === 'pdf') {
      return 'pdf';
    }
    if (
      contentType.includes('spreadsheet') ||
      contentType === 'text/csv' ||
      ['csv', 'xls', 'xlsx'].includes(extension)
    ) {
      return 'spreadsheet';
    }
    if (
      contentType.includes('presentation') ||
      ['ppt', 'pptx'].includes(extension)
    ) {
      return 'presentation';
    }
    if (
      contentType.startsWith('text/') ||
      contentType.includes('document') ||
      ['doc', 'docx', 'json', 'md', 'txt'].includes(extension)
    ) {
      return 'document';
    }
    return 'other';
  }

  private preserveExtension(
    item: LibraryItemRecord,
    requestedName: string,
  ): string {
    if (item.itemType === 'folder') {
      return requestedName;
    }
    const index = item.name.lastIndexOf('.');
    if (index <= 0) {
      return requestedName;
    }
    const extension = item.name.slice(index);
    const requestedBase = requestedName
      .toLocaleLowerCase()
      .endsWith(extension.toLocaleLowerCase())
      ? requestedName.slice(0, -extension.length)
      : requestedName;
    const normalized = requestedBase.trim();
    if (!normalized) {
      throw new ConversationValidationError('File name cannot be empty');
    }
    return `${normalized}${extension}`.slice(0, 255);
  }

  private toDownloadEntry(
    record: LibraryDownloadRecord,
    rowById: Map<string, LibraryItemRecord>,
    roots: LibraryItemRecord[],
  ): LibraryDownloadEntry {
    const path = this.buildPath(rowById, record.id, true);
    const rootIds = new Set(roots.map((root) => root.id));
    const relative = path
      .slice(
        Math.max(
          0,
          path.findIndex((segment) => rootIds.has(segment.id)),
        ),
      )
      .map((segment) => segment.name)
      .join('/');
    return {
      content: record.content,
      contentType: record.contentType ?? 'application/octet-stream',
      id: record.id,
      name: record.name,
      path: relative || record.name,
      pathname: record.pathname,
      size: record.size,
      url: record.url,
    };
  }

  private encodeCursor(offset: number): string {
    return Buffer.from(String(offset)).toString('base64url');
  }

  private decodeCursor(cursor?: string): number {
    if (!cursor) {
      return 0;
    }
    const parsed = Number(Buffer.from(cursor, 'base64url').toString('utf8'));
    if (!Number.isInteger(parsed) || parsed < 0) {
      throw new ConversationValidationError('Invalid library cursor');
    }
    return parsed;
  }
}
