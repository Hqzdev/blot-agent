'use client';

import type {
  LibraryFileCategory,
  LibraryItem,
  LibraryListResult,
  LibrarySort,
  LibrarySource,
  LibraryTab,
} from '@teya/contracts';
import { upload as uploadBlob } from '@vercel/blob/client';
import {
  ArrowDown,
  ArrowUp,
  Check,
  ChevronDown,
  ChevronRight,
  Download,
  File,
  FileImage,
  FileSpreadsheet,
  FileText,
  Filter,
  Folder,
  FolderPlus,
  Grid2X2,
  ImageIcon,
  List,
  Loader2,
  MoreHorizontal,
  Move,
  Pencil,
  Plus,
  Presentation,
  Search,
  Trash2,
  Upload,
  X,
} from 'lucide-react';
import Image from 'next/image';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { toast } from 'sonner';
import useSWR, { useSWRConfig } from 'swr';

import { Button } from '@/components/ui/button';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from '@/components/ui/dropdown-menu';
import { Input } from '@/components/ui/input';
import { cn, fetcher } from '@/lib/utils';

type LibraryView = 'list' | 'grid';
type EditorMode = 'folder' | 'rename' | null;

const acceptedFiles =
  '.png,.jpg,.jpeg,.webp,.gif,.pdf,.txt,.md,.csv,.json,.c,.cpp,.cs,.go,.h,.hpp,.html,.java,.js,.jsx,.kt,.php,.py,.rb,.rs,.scss,.sh,.sql,.swift,.ts,.tsx,.xml,.yaml,.yml,.doc,.docx,.xls,.xlsx,.ppt,.pptx';

const categoryLabels: Array<{
  icon: typeof ImageIcon;
  label: string;
  value: LibraryFileCategory;
}> = [
  { icon: ImageIcon, label: 'Images', value: 'image' },
  { icon: FileText, label: 'Documents', value: 'document' },
  { icon: FileSpreadsheet, label: 'Spreadsheets', value: 'spreadsheet' },
  { icon: Presentation, label: 'Presentations', value: 'presentation' },
  { icon: File, label: 'PDFs', value: 'pdf' },
];

export function LibraryPage() {
  const uploadRef = useRef<HTMLInputElement>(null);
  const { mutate: mutateCache } = useSWRConfig();
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [parentId, setParentId] = useState<string | null>(null);
  const [tab, setTab] = useState<LibraryTab>('all');
  const [source, setSource] = useState<LibrarySource | undefined>();
  const [category, setCategory] = useState<LibraryFileCategory | undefined>();
  const [deleted, setDeleted] = useState(false);
  const [sort, setSort] = useState<LibrarySort>('modified');
  const [direction, setDirection] = useState<'asc' | 'desc'>('desc');
  const [view, setView] = useState<LibraryView>('list');
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [extraItems, setExtraItems] = useState<LibraryItem[]>([]);
  const [nextCursor, setNextCursor] = useState<string | null>(null);
  const [loadingMore, setLoadingMore] = useState(false);
  const [uploadProgress, setUploadProgress] = useState<number | null>(null);
  const [editorMode, setEditorMode] = useState<EditorMode>(null);
  const [editingItem, setEditingItem] = useState<LibraryItem | null>(null);
  const [editorValue, setEditorValue] = useState('');
  const [editorBusy, setEditorBusy] = useState(false);
  const [moveIds, setMoveIds] = useState<string[]>([]);

  useEffect(() => {
    const timer = window.setTimeout(() => setDebouncedQuery(query.trim()), 250);
    return () => window.clearTimeout(timer);
  }, [query]);

  useEffect(() => {
    const stored = window.localStorage.getItem('library:view');
    if (stored === 'grid' || stored === 'list') {
      setView(stored);
    }
  }, []);

  const queryString = useMemo(() => {
    const params = new URLSearchParams({
      deleted: String(deleted),
      direction,
      limit: '100',
      sort,
      tab,
    });
    if (parentId && !debouncedQuery && !deleted) {
      params.set('parentId', parentId);
    }
    if (debouncedQuery) {
      params.set('query', debouncedQuery);
    }
    if (source) {
      params.set('source', source);
    }
    if (category) {
      params.set('category', category);
    }
    return params.toString();
  }, [
    category,
    debouncedQuery,
    deleted,
    direction,
    parentId,
    sort,
    source,
    tab,
  ]);

  const apiKey = `/app/api/library/items?${queryString}`;
  const { data, error, isLoading, mutate } = useSWR<LibraryListResult>(
    apiKey,
    fetcher,
  );

  useEffect(() => {
    setExtraItems([]);
    setNextCursor(data?.nextCursor ?? null);
    setSelected(new Set());
  }, [data, apiKey]);

  const items = useMemo(
    () => [...(data?.items ?? []), ...extraItems],
    [data?.items, extraItems],
  );

  const refresh = useCallback(async () => {
    setExtraItems([]);
    setSelected(new Set());
    await mutateCache(
      (key) =>
        typeof key === 'string' && key.startsWith('/app/api/library/items?'),
    );
  }, [mutateCache]);

  const request = useCallback(
    async (url: string, init: RequestInit, success: string) => {
      const response = await fetch(url, init);
      if (!response.ok) {
        const payload = await response.json().catch(() => null);
        throw new Error(payload?.error ?? 'Library request failed');
      }
      await refresh();
      toast.success(success);
    },
    [refresh],
  );

  const setLibraryView = (next: LibraryView) => {
    setView(next);
    window.localStorage.setItem('library:view', next);
  };

  const openCreateFolder = () => {
    setEditingItem(null);
    setEditorValue('');
    setEditorMode('folder');
  };

  const openRename = (item: LibraryItem) => {
    setEditingItem(item);
    setEditorValue(fileBaseName(item));
    setEditorMode('rename');
  };

  const saveEditor = async () => {
    if (!editorValue.trim()) {
      return;
    }
    setEditorBusy(true);
    try {
      if (editorMode === 'folder') {
        await request(
          '/app/api/library/folders',
          {
            body: JSON.stringify({ name: editorValue, parentId }),
            headers: { 'Content-Type': 'application/json' },
            method: 'POST',
          },
          'Folder created',
        );
      } else if (editingItem) {
        await request(
          `/app/api/library/items/${editingItem.id}`,
          {
            body: JSON.stringify({ name: editorValue }),
            headers: { 'Content-Type': 'application/json' },
            method: 'PATCH',
          },
          'Item renamed',
        );
      }
      setEditorMode(null);
    } catch (requestError) {
      toast.error(errorMessage(requestError));
    } finally {
      setEditorBusy(false);
    }
  };

  const uploadFiles = async (files: FileList | null) => {
    if (!files?.length) {
      return;
    }
    const selectedFiles = Array.from(files);
    let completed = 0;
    setUploadProgress(0);
    try {
      for (const file of selectedFiles) {
        await uploadFile(file, parentId, (progress) => {
          setUploadProgress(
            Math.round(
              ((completed + progress / 100) / selectedFiles.length) * 100,
            ),
          );
        });
        completed += 1;
      }
      toast.success(
        selectedFiles.length === 1
          ? 'File uploaded'
          : `${selectedFiles.length} files uploaded`,
      );
      await refresh();
    } catch (uploadError) {
      toast.error(errorMessage(uploadError));
    } finally {
      setUploadProgress(null);
      if (uploadRef.current) {
        uploadRef.current.value = '';
      }
    }
  };

  const trashItems = async (ids: string[]) => {
    if (!window.confirm('Move the selected item(s) to Recently deleted?')) {
      return;
    }
    try {
      await request(
        '/app/api/library/items/bulk',
        {
          body: JSON.stringify({ action: 'trash', ids }),
          headers: { 'Content-Type': 'application/json' },
          method: 'POST',
        },
        'Moved to Recently deleted',
      );
    } catch (requestError) {
      toast.error(errorMessage(requestError));
    }
  };

  const restoreItems = async (ids: string[]) => {
    try {
      await request(
        '/app/api/library/items/bulk',
        {
          body: JSON.stringify({ action: 'restore', ids }),
          headers: { 'Content-Type': 'application/json' },
          method: 'POST',
        },
        'Item restored',
      );
    } catch (requestError) {
      toast.error(errorMessage(requestError));
    }
  };

  const permanentlyDelete = async (ids: string[]) => {
    if (
      !window.confirm(
        'Delete the selected item(s) permanently? This cannot be undone.',
      )
    ) {
      return;
    }
    try {
      await request(
        '/app/api/library/items/bulk',
        {
          body: JSON.stringify({ action: 'permanent', ids }),
          headers: { 'Content-Type': 'application/json' },
          method: 'POST',
        },
        'Item permanently deleted',
      );
    } catch (requestError) {
      toast.error(errorMessage(requestError));
    }
  };

  const moveItems = async (destinationId: string | null) => {
    try {
      await request(
        '/app/api/library/items/bulk',
        {
          body: JSON.stringify({
            action: 'move',
            ids: moveIds,
            parentId: destinationId,
          }),
          headers: { 'Content-Type': 'application/json' },
          method: 'POST',
        },
        'Item moved',
      );
      setMoveIds([]);
    } catch (requestError) {
      toast.error(errorMessage(requestError));
    }
  };

  const downloadZip = async (ids: string[]) => {
    try {
      const response = await fetch('/app/api/library/download', {
        body: JSON.stringify({ ids }),
        headers: { 'Content-Type': 'application/json' },
        method: 'POST',
      });
      if (!response.ok) {
        const payload = await response.json().catch(() => null);
        throw new Error(payload?.error ?? 'Download failed');
      }
      saveBlob(await response.blob(), 'teya-library.zip');
    } catch (downloadError) {
      toast.error(errorMessage(downloadError));
    }
  };

  const loadMore = async () => {
    if (!nextCursor) {
      return;
    }
    setLoadingMore(true);
    try {
      const response = await fetch(
        `/app/api/library/items?${queryString}&cursor=${encodeURIComponent(nextCursor)}`,
      );
      if (!response.ok) {
        throw new Error('Unable to load more items');
      }
      const page = (await response.json()) as LibraryListResult;
      setExtraItems((current) => [...current, ...page.items]);
      setNextCursor(page.nextCursor);
    } catch (loadError) {
      toast.error(errorMessage(loadError));
    } finally {
      setLoadingMore(false);
    }
  };

  const allSelected =
    items.length > 0 && items.every((item) => selected.has(item.id));
  const toggleAll = () =>
    setSelected(
      allSelected ? new Set() : new Set(items.map((item) => item.id)),
    );
  const toggleItem = (id: string) =>
    setSelected((current) => {
      const next = new Set(current);
      if (next.has(id)) {
        next.delete(id);
      } else {
        next.add(id);
      }
      return next;
    });

  const openFolder = (item: LibraryItem) => {
    if (item.itemType !== 'folder' || deleted) {
      return;
    }
    setParentId(item.id);
    setQuery('');
  };

  return (
    <main className="h-dvh overflow-y-auto bg-[var(--chat-paper)] text-[var(--chat-ink)]">
      <div className="mx-auto w-full max-w-[1120px] px-4 pb-28 pt-10 sm:px-8 lg:pt-20">
        <header className="flex flex-col gap-5 md:flex-row md:items-center md:justify-between">
          <h1 className="text-2xl font-semibold tracking-tight">Library</h1>
          <div className="flex w-full items-center gap-2 md:w-auto">
            <div className="relative min-w-0 flex-1 md:w-[300px]">
              <Search className="absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--chat-hollow)]" />
              <Input
                aria-label="Search Library"
                value={query}
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search"
                className="h-10 rounded-full border-[var(--chat-hairline)] bg-transparent pl-9 shadow-none"
              />
            </div>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <Button className="h-10 rounded-full bg-[var(--chat-ink)] px-4 text-[var(--chat-paper)] hover:bg-[var(--chat-ink)]/85">
                  New
                  <ChevronDown className="ml-1 size-4" />
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent
                align="end"
                className="w-48 rounded-[16px] p-2"
              >
                <DropdownMenuItem
                  className="rounded-[10px]"
                  onSelect={() => uploadRef.current?.click()}
                >
                  <Upload />
                  Upload
                </DropdownMenuItem>
                <DropdownMenuItem
                  className="rounded-[10px]"
                  onSelect={openCreateFolder}
                >
                  <FolderPlus />
                  Folder
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
            <input
              ref={uploadRef}
              type="file"
              className="hidden"
              accept={acceptedFiles}
              multiple
              onChange={(event) => void uploadFiles(event.target.files)}
            />
          </div>
        </header>

        {uploadProgress !== null && (
          <div className="mt-5 overflow-hidden rounded-full bg-[var(--chat-hover)]">
            <div
              className="h-1.5 rounded-full bg-[#0b84ff] transition-[width]"
              style={{ width: `${uploadProgress}%` }}
            />
          </div>
        )}

        <div className="mt-10 flex flex-wrap items-center gap-2">
          {(['all', 'images', 'documents'] as LibraryTab[]).map((value) => (
            <Button
              key={value}
              variant="ghost"
              onClick={() => {
                setTab(value);
                setCategory(undefined);
                setDeleted(false);
              }}
              className={cn(
                'h-9 rounded-full px-4 capitalize text-[var(--chat-hollow)] shadow-none',
                tab === value &&
                  !deleted &&
                  'bg-[var(--chat-hover)] text-[var(--chat-ink)]',
              )}
            >
              {value}
            </Button>
          ))}
          <div className="ml-auto flex items-center gap-1">
            <FilterMenu
              category={category}
              deleted={deleted}
              source={source}
              onCategory={(value) => {
                setCategory(value);
                setDeleted(false);
              }}
              onDeleted={() => {
                setDeleted(true);
                setCategory(undefined);
                setSource(undefined);
                setParentId(null);
              }}
              onReset={() => {
                setCategory(undefined);
                setDeleted(false);
                setSource(undefined);
              }}
              onSource={(value) => {
                setSource(value);
                setDeleted(false);
              }}
            />
            <SortMenu
              direction={direction}
              sort={sort}
              onChange={(nextSort, nextDirection) => {
                setSort(nextSort);
                setDirection(nextDirection);
              }}
            />
            <span className="mx-1 h-6 w-px bg-[var(--chat-hairline)]" />
            <Button
              variant="ghost"
              size="icon"
              aria-label="Grid view"
              onClick={() => setLibraryView('grid')}
              className={cn(
                'rounded-full text-[var(--chat-hollow)]',
                view === 'grid' &&
                  'bg-[var(--chat-hover)] text-[var(--chat-ink)]',
              )}
            >
              <Grid2X2 className="size-4" />
            </Button>
            <Button
              variant="ghost"
              size="icon"
              aria-label="List view"
              onClick={() => setLibraryView('list')}
              className={cn(
                'rounded-full text-[var(--chat-hollow)]',
                view === 'list' &&
                  'bg-[var(--chat-hover)] text-[var(--chat-ink)]',
              )}
            >
              <List className="size-4" />
            </Button>
          </div>
        </div>

        <Breadcrumbs
          path={data?.breadcrumbs ?? []}
          hidden={deleted || Boolean(debouncedQuery)}
          onNavigate={setParentId}
        />

        {isLoading ? (
          <StateMessage icon={<Loader2 className="size-6 animate-spin" />}>
            Loading your Library…
          </StateMessage>
        ) : error ? (
          <StateMessage icon={<X className="size-6" />}>
            Could not load your Library
            <Button
              variant="outline"
              className="mt-3 rounded-full"
              onClick={() => void mutate()}
            >
              Try again
            </Button>
          </StateMessage>
        ) : items.length === 0 ? (
          <StateMessage icon={<Folder className="size-6" />}>
            {debouncedQuery
              ? `No results for “${debouncedQuery}”`
              : deleted
                ? 'Recently deleted is empty'
                : 'No files here yet'}
          </StateMessage>
        ) : view === 'list' ? (
          <LibraryList
            allSelected={allSelected}
            deleted={deleted}
            items={items}
            selected={selected}
            onDownload={(item) =>
              window.location.assign(
                `/app/api/library/items/${item.id}/download`,
              )
            }
            onMove={(item) => setMoveIds([item.id])}
            onOpen={openFolder}
            onPermanent={(item) => void permanentlyDelete([item.id])}
            onRename={openRename}
            onRestore={(item) => void restoreItems([item.id])}
            onToggle={toggleItem}
            onToggleAll={toggleAll}
            onTrash={(item) => void trashItems([item.id])}
          />
        ) : (
          <LibraryGrid
            deleted={deleted}
            items={items}
            selected={selected}
            onDownload={(item) =>
              window.location.assign(
                `/app/api/library/items/${item.id}/download`,
              )
            }
            onMove={(item) => setMoveIds([item.id])}
            onOpen={openFolder}
            onPermanent={(item) => void permanentlyDelete([item.id])}
            onRename={openRename}
            onRestore={(item) => void restoreItems([item.id])}
            onToggle={toggleItem}
            onTrash={(item) => void trashItems([item.id])}
          />
        )}

        {nextCursor && (
          <div className="mt-8 flex justify-center">
            <Button
              variant="outline"
              className="rounded-full"
              disabled={loadingMore}
              onClick={() => void loadMore()}
            >
              {loadingMore && <Loader2 className="mr-2 size-4 animate-spin" />}
              Load more
            </Button>
          </div>
        )}
      </div>

      {selected.size > 0 && (
        <SelectionBar
          deleted={deleted}
          count={selected.size}
          onClear={() => setSelected(new Set())}
          onDelete={() =>
            void (deleted
              ? permanentlyDelete([...selected])
              : trashItems([...selected]))
          }
          onDownload={() => void downloadZip([...selected])}
          onMove={() => setMoveIds([...selected])}
          onRestore={() => void restoreItems([...selected])}
        />
      )}

      <NameDialog
        busy={editorBusy}
        mode={editorMode}
        value={editorValue}
        onChange={setEditorValue}
        onClose={() => setEditorMode(null)}
        onSave={() => void saveEditor()}
      />

      <FolderPickerDialog
        open={moveIds.length > 0}
        excludedIds={moveIds}
        onClose={() => setMoveIds([])}
        onMove={(destinationId) => void moveItems(destinationId)}
      />
    </main>
  );
}

function FilterMenu({
  category,
  deleted,
  source,
  onCategory,
  onDeleted,
  onReset,
  onSource,
}: {
  category?: LibraryFileCategory;
  deleted: boolean;
  source?: LibrarySource;
  onCategory: (value: LibraryFileCategory) => void;
  onDeleted: () => void;
  onReset: () => void;
  onSource: (value: LibrarySource) => void;
}) {
  const active = Boolean(category || deleted || source);
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          aria-label="Filter Library"
          className={cn(
            'rounded-full text-[var(--chat-hollow)]',
            active && 'bg-[var(--chat-hover)] text-[var(--chat-ink)]',
          )}
        >
          <Filter className="size-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-60 rounded-[16px] p-2">
        <DropdownMenuLabel className="text-xs text-[var(--chat-hollow)]">
          Source
        </DropdownMenuLabel>
        <FilterItem
          active={source === 'uploaded'}
          icon={Upload}
          label="Uploaded"
          onSelect={() => onSource('uploaded')}
        />
        <FilterItem
          active={source === 'generated'}
          icon={Plus}
          label="Generated"
          onSelect={() => onSource('generated')}
        />
        <DropdownMenuSeparator />
        <DropdownMenuLabel className="text-xs text-[var(--chat-hollow)]">
          File type
        </DropdownMenuLabel>
        {categoryLabels.map((item) => (
          <FilterItem
            key={item.value}
            active={category === item.value}
            icon={item.icon}
            label={item.label}
            onSelect={() => onCategory(item.value)}
          />
        ))}
        <DropdownMenuSeparator />
        <FilterItem
          active={!active}
          icon={File}
          label="Show all file types"
          onSelect={onReset}
        />
        <FilterItem
          active={deleted}
          danger
          icon={Trash2}
          label="Recently deleted"
          onSelect={onDeleted}
        />
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function FilterItem({
  active,
  danger = false,
  icon: Icon,
  label,
  onSelect,
}: {
  active: boolean;
  danger?: boolean;
  icon: typeof File;
  label: string;
  onSelect: () => void;
}) {
  return (
    <DropdownMenuItem
      onSelect={onSelect}
      className={cn(
        'rounded-[10px]',
        danger && 'text-destructive focus:text-destructive',
      )}
    >
      <Icon />
      <span>{label}</span>
      {active && <Check className="ml-auto" />}
    </DropdownMenuItem>
  );
}

function SortMenu({
  direction,
  sort,
  onChange,
}: {
  direction: 'asc' | 'desc';
  sort: LibrarySort;
  onChange: (sort: LibrarySort, direction: 'asc' | 'desc') => void;
}) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          aria-label="Sort Library"
          className="rounded-full text-[var(--chat-hollow)]"
        >
          {direction === 'asc' ? (
            <ArrowUp className="size-4" />
          ) : (
            <ArrowDown className="size-4" />
          )}
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-48 rounded-[16px] p-2">
        {(['name', 'modified', 'size'] as LibrarySort[]).map((value) => (
          <DropdownMenuItem
            key={value}
            className="rounded-[10px] capitalize"
            onSelect={() =>
              onChange(
                value,
                value === sort && direction === 'asc' ? 'desc' : 'asc',
              )
            }
          >
            {value}
            {sort === value &&
              (direction === 'asc' ? (
                <ArrowUp className="ml-auto" />
              ) : (
                <ArrowDown className="ml-auto" />
              ))}
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function Breadcrumbs({
  hidden,
  path,
  onNavigate,
}: {
  hidden: boolean;
  path: Array<{ id: string; name: string }>;
  onNavigate: (id: string | null) => void;
}) {
  if (hidden || path.length === 0) {
    return <div className="h-7" />;
  }
  return (
    <nav className="flex h-7 items-center gap-1 overflow-x-auto text-sm text-[var(--chat-hollow)]">
      <button
        type="button"
        onClick={() => onNavigate(null)}
        className="hover:text-[var(--chat-ink)]"
      >
        Library
      </button>
      {path.map((segment) => (
        <span key={segment.id} className="flex items-center gap-1">
          <ChevronRight className="size-3.5" />
          <button
            type="button"
            onClick={() => onNavigate(segment.id)}
            className="whitespace-nowrap hover:text-[var(--chat-ink)]"
          >
            {segment.name}
          </button>
        </span>
      ))}
    </nav>
  );
}

function LibraryList(
  props: LibraryItemsProps & {
    allSelected: boolean;
    onToggleAll: () => void;
  },
) {
  return (
    <div className="mt-2">
      <div className="grid grid-cols-[36px_minmax(0,1fr)_120px_100px_40px] items-center gap-3 border-b border-[var(--chat-hairline)] px-2 py-3 text-xs text-[var(--chat-hollow)] max-sm:grid-cols-[36px_minmax(0,1fr)_40px]">
        <SelectionCheckbox
          checked={props.allSelected}
          onChange={props.onToggleAll}
          label="Select all"
        />
        <span>Name</span>
        <span className="max-sm:hidden">Modified</span>
        <span className="max-sm:hidden">Size</span>
        <span />
      </div>
      {props.items.map((item) => (
        <div
          key={item.id}
          className="group grid min-h-16 grid-cols-[36px_minmax(0,1fr)_120px_100px_40px] items-center gap-3 border-b border-[var(--chat-hairline)] px-2 transition-colors hover:rounded-[14px] hover:bg-[var(--chat-hover)] max-sm:grid-cols-[36px_minmax(0,1fr)_40px]"
        >
          <SelectionCheckbox
            checked={props.selected.has(item.id)}
            onChange={() => props.onToggle(item.id)}
            label={`Select ${item.name}`}
          />
          <button
            type="button"
            onClick={() => props.onOpen(item)}
            className="flex min-w-0 items-center gap-3 py-2 text-left"
          >
            <ItemThumbnail item={item} size={38} />
            <span className="min-w-0">
              <span className="block truncate text-sm font-medium">
                {item.name}
              </span>
              {item.path.length > 0 && (
                <span className="block truncate text-xs text-[var(--chat-hollow)]">
                  {item.path.map((segment) => segment.name).join(' / ')}
                </span>
              )}
            </span>
          </button>
          <span className="text-sm text-[var(--chat-hollow)] max-sm:hidden">
            {formatModified(item.updatedAt)}
          </span>
          <span className="text-sm text-[var(--chat-hollow)] max-sm:hidden">
            {item.itemType === 'folder' ? '—' : formatBytes(item.size)}
          </span>
          <ItemMenu item={item} {...props} />
        </div>
      ))}
    </div>
  );
}

function LibraryGrid(props: LibraryItemsProps) {
  return (
    <div className="mt-2 grid grid-cols-2 gap-4 md:grid-cols-3 xl:grid-cols-4">
      {props.items.map((item) => (
        <article
          key={item.id}
          className={cn(
            'group relative flex aspect-[.9] min-h-[210px] flex-col overflow-hidden rounded-[24px] border border-[var(--chat-hairline)] bg-[var(--chat-sidebar-mist)] p-5 transition-shadow hover:shadow-lg',
            props.selected.has(item.id) && 'ring-2 ring-[#0b84ff]',
          )}
        >
          <div className="absolute right-3 top-3 z-10 flex items-center gap-1">
            <SelectionCheckbox
              checked={props.selected.has(item.id)}
              onChange={() => props.onToggle(item.id)}
              label={`Select ${item.name}`}
            />
            <ItemMenu item={item} {...props} />
          </div>
          <button
            type="button"
            onClick={() => props.onOpen(item)}
            className="flex min-h-0 flex-1 flex-col text-left"
          >
            <span className="line-clamp-2 pr-16 text-sm font-semibold">
              {item.name}
            </span>
            <span className="flex flex-1 items-center justify-center py-4">
              <ItemThumbnail item={item} size={96} />
            </span>
            <span className="text-xs uppercase text-[var(--chat-hollow)]">
              {item.itemType === 'folder'
                ? 'Folder'
                : `${extensionOf(item.name)} · ${formatBytes(item.size)}`}
            </span>
          </button>
        </article>
      ))}
    </div>
  );
}

type LibraryItemsProps = {
  deleted: boolean;
  items: LibraryItem[];
  selected: Set<string>;
  onDownload: (item: LibraryItem) => void;
  onMove: (item: LibraryItem) => void;
  onOpen: (item: LibraryItem) => void;
  onPermanent: (item: LibraryItem) => void;
  onRename: (item: LibraryItem) => void;
  onRestore: (item: LibraryItem) => void;
  onToggle: (id: string) => void;
  onTrash: (item: LibraryItem) => void;
};

function ItemMenu({
  deleted,
  item,
  onDownload,
  onMove,
  onPermanent,
  onRename,
  onRestore,
  onTrash,
}: LibraryItemsProps & { item: LibraryItem }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger asChild>
        <Button
          variant="ghost"
          size="icon"
          aria-label={`Actions for ${item.name}`}
          className="size-8 rounded-[10px] opacity-50 group-hover:opacity-100 data-[state=open]:bg-[var(--chat-paper)] data-[state=open]:opacity-100"
        >
          <MoreHorizontal className="size-4" />
        </Button>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-48 rounded-[16px] p-2">
        {deleted ? (
          <>
            <DropdownMenuItem
              className="rounded-[10px]"
              onSelect={() => onRestore(item)}
            >
              <ArrowUp />
              Restore
            </DropdownMenuItem>
            <DropdownMenuItem
              className="rounded-[10px] text-destructive focus:text-destructive"
              onSelect={() => onPermanent(item)}
            >
              <Trash2 />
              Delete permanently
            </DropdownMenuItem>
          </>
        ) : (
          <>
            <DropdownMenuItem
              className="rounded-[10px]"
              onSelect={() => onDownload(item)}
            >
              <Download />
              Download
            </DropdownMenuItem>
            <DropdownMenuItem
              className="rounded-[10px]"
              onSelect={() => onRename(item)}
            >
              <Pencil />
              Rename
            </DropdownMenuItem>
            <DropdownMenuItem
              className="rounded-[10px]"
              onSelect={() => onMove(item)}
            >
              <Move />
              Move
            </DropdownMenuItem>
            <DropdownMenuItem
              className="rounded-[10px] text-destructive focus:text-destructive"
              onSelect={() => onTrash(item)}
            >
              <Trash2 />
              Delete
            </DropdownMenuItem>
          </>
        )}
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

function ItemThumbnail({ item, size }: { item: LibraryItem; size: number }) {
  const category = itemCategory(item);
  if (category === 'image' && !item.deletedAt) {
    return (
      <span
        className="relative shrink-0 overflow-hidden rounded-[10px] border border-[var(--chat-hairline)]"
        style={{ height: size, width: size }}
      >
        <Image
          src={item.url ?? `/app/api/library/items/${item.id}/thumbnail`}
          alt=""
          fill
          sizes={`${size}px`}
          className="object-cover"
          unoptimized
        />
      </span>
    );
  }
  const Icon =
    item.itemType === 'folder'
      ? Folder
      : category === 'image'
        ? FileImage
        : category === 'spreadsheet'
          ? FileSpreadsheet
          : category === 'presentation'
            ? Presentation
            : category === 'document' || category === 'pdf'
              ? FileText
              : File;
  return (
    <span
      className="flex shrink-0 items-center justify-center rounded-[10px] border border-[var(--chat-hairline)] bg-[var(--chat-paper)] text-[var(--chat-hollow)]"
      style={{ height: size, width: size }}
    >
      <Icon
        style={{
          height: Math.max(18, size * 0.36),
          width: Math.max(18, size * 0.36),
        }}
      />
    </span>
  );
}

function SelectionCheckbox({
  checked,
  label,
  onChange,
}: {
  checked: boolean;
  label: string;
  onChange: () => void;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      aria-pressed={checked}
      onClick={(event) => {
        event.stopPropagation();
        onChange();
      }}
      className={cn(
        'flex size-[18px] items-center justify-center rounded-[5px] border border-[var(--chat-hairline)] bg-[var(--chat-paper)] text-white',
        checked && 'border-[#0b84ff] bg-[#0b84ff]',
      )}
    >
      {checked && <Check className="size-3" strokeWidth={3} />}
    </button>
  );
}

function SelectionBar({
  count,
  deleted,
  onClear,
  onDelete,
  onDownload,
  onMove,
  onRestore,
}: {
  count: number;
  deleted: boolean;
  onClear: () => void;
  onDelete: () => void;
  onDownload: () => void;
  onMove: () => void;
  onRestore: () => void;
}) {
  return (
    <div className="fixed bottom-5 left-1/2 z-40 flex max-w-[calc(100vw-24px)] -translate-x-1/2 items-center gap-1 rounded-full border border-[var(--chat-hairline)] bg-[var(--chat-paper)] p-2 shadow-xl">
      <span className="whitespace-nowrap px-3 text-sm font-medium">
        {count} selected
      </span>
      {deleted ? (
        <Button variant="ghost" className="rounded-full" onClick={onRestore}>
          Restore
        </Button>
      ) : (
        <>
          <Button
            variant="ghost"
            className="rounded-full max-sm:hidden"
            onClick={onMove}
          >
            Move
          </Button>
          <Button
            variant="ghost"
            className="rounded-full max-sm:hidden"
            onClick={onDownload}
          >
            Download ZIP
          </Button>
        </>
      )}
      <Button
        variant="ghost"
        className="rounded-full text-destructive hover:text-destructive"
        onClick={onDelete}
      >
        Delete
      </Button>
      <Button
        variant="ghost"
        size="icon"
        className="rounded-full"
        onClick={onClear}
        aria-label="Clear selection"
      >
        <X className="size-4" />
      </Button>
    </div>
  );
}

function NameDialog({
  busy,
  mode,
  value,
  onChange,
  onClose,
  onSave,
}: {
  busy: boolean;
  mode: EditorMode;
  value: string;
  onChange: (value: string) => void;
  onClose: () => void;
  onSave: () => void;
}) {
  return (
    <Dialog open={mode !== null} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="rounded-[20px]">
        <DialogHeader>
          <DialogTitle>
            {mode === 'folder' ? 'New folder' : 'Rename item'}
          </DialogTitle>
          <DialogDescription>
            {mode === 'folder'
              ? 'Create a folder in the current location.'
              : 'The original file extension will be preserved.'}
          </DialogDescription>
        </DialogHeader>
        <Input
          autoFocus
          maxLength={255}
          value={value}
          onChange={(event) => onChange(event.target.value)}
          onKeyDown={(event) => event.key === 'Enter' && onSave()}
          className="rounded-[10px] shadow-none"
        />
        <DialogFooter>
          <Button variant="ghost" className="rounded-full" onClick={onClose}>
            Cancel
          </Button>
          <Button
            className="rounded-full"
            disabled={busy || !value.trim()}
            onClick={onSave}
          >
            {busy && <Loader2 className="mr-2 size-4 animate-spin" />}
            Save
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function FolderPickerDialog({
  excludedIds,
  open,
  onClose,
  onMove,
}: {
  excludedIds: string[];
  open: boolean;
  onClose: () => void;
  onMove: (destinationId: string | null) => void;
}) {
  const [folderId, setFolderId] = useState<string | null>(null);
  const params = new URLSearchParams({
    deleted: 'false',
    direction: 'asc',
    limit: '100',
    sort: 'name',
    tab: 'all',
  });
  if (folderId) {
    params.set('parentId', folderId);
  }
  const { data, isLoading } = useSWR<LibraryListResult>(
    open ? `/app/api/library/items?${params}` : null,
    fetcher,
  );
  const excluded = new Set(excludedIds);
  const folders = (data?.items ?? []).filter(
    (item) => item.itemType === 'folder' && !excluded.has(item.id),
  );
  return (
    <Dialog
      open={open}
      onOpenChange={(nextOpen) => {
        if (!nextOpen) {
          setFolderId(null);
          onClose();
        }
      }}
    >
      <DialogContent className="rounded-[20px]">
        <DialogHeader>
          <DialogTitle>Move to folder</DialogTitle>
          <DialogDescription>
            Choose a destination. Chat and project links will stay unchanged.
          </DialogDescription>
        </DialogHeader>
        <Breadcrumbs
          hidden={false}
          path={data?.breadcrumbs ?? []}
          onNavigate={setFolderId}
        />
        <div className="max-h-72 min-h-36 overflow-y-auto rounded-[14px] border border-[var(--chat-hairline)] p-1">
          {isLoading ? (
            <div className="flex h-32 items-center justify-center">
              <Loader2 className="size-5 animate-spin" />
            </div>
          ) : folders.length === 0 ? (
            <div className="flex h-32 items-center justify-center text-sm text-[var(--chat-hollow)]">
              No folders here
            </div>
          ) : (
            folders.map((folder) => (
              <button
                key={folder.id}
                type="button"
                className="flex w-full items-center gap-3 rounded-[10px] px-3 py-2 text-left hover:bg-[var(--chat-hover)]"
                onClick={() => setFolderId(folder.id)}
              >
                <Folder className="size-5" />
                <span className="truncate text-sm">{folder.name}</span>
                <ChevronRight className="ml-auto size-4 text-[var(--chat-hollow)]" />
              </button>
            ))
          )}
        </div>
        <DialogFooter>
          <Button variant="ghost" className="rounded-full" onClick={onClose}>
            Cancel
          </Button>
          <Button className="rounded-full" onClick={() => onMove(folderId)}>
            Move here
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function StateMessage({
  children,
  icon,
}: {
  children: React.ReactNode;
  icon: React.ReactNode;
}) {
  return (
    <div className="flex min-h-[360px] flex-col items-center justify-center text-center text-sm text-[var(--chat-hollow)]">
      <span className="mb-4 flex size-12 items-center justify-center rounded-[14px] bg-[var(--chat-hover)]">
        {icon}
      </span>
      {children}
    </div>
  );
}

function itemCategory(item: LibraryItem): LibraryFileCategory {
  const contentType = item.contentType?.toLocaleLowerCase() ?? '';
  const extension = extensionOf(item.name).toLocaleLowerCase();
  if (contentType.startsWith('image/')) return 'image';
  if (contentType === 'application/pdf' || extension === 'pdf') return 'pdf';
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

function fileBaseName(item: LibraryItem): string {
  if (item.itemType === 'folder') {
    return item.name;
  }
  const index = item.name.lastIndexOf('.');
  return index > 0 ? item.name.slice(0, index) : item.name;
}

function extensionOf(name: string): string {
  const extension = name.split('.').at(-1);
  return extension && extension !== name ? extension.toUpperCase() : 'FILE';
}

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
}

function formatModified(value: Date): string {
  const date = new Date(value);
  const now = new Date();
  if (date.toDateString() === now.toDateString()) {
    return 'Today';
  }
  return new Intl.DateTimeFormat('en', {
    day: 'numeric',
    month: 'short',
  }).format(date);
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : 'Library request failed';
}

function saveBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

function uploadFile(
  file: File,
  parentId: string | null,
  onProgress: (progress: number) => void,
): Promise<void> {
  return uploadDirect(file, parentId, onProgress).catch(() =>
    uploadThroughServer(file, parentId, onProgress),
  );
}

async function uploadDirect(
  file: File,
  parentId: string | null,
  onProgress: (progress: number) => void,
): Promise<void> {
  const extension = file.name.toLocaleLowerCase().match(/\.[a-z0-9]{1,10}$/);
  const pathname = `library/${crypto.randomUUID()}${extension?.[0] ?? ''}`;
  onProgress(5);
  await uploadBlob(pathname, file, {
    access: 'public',
    clientPayload: JSON.stringify({
      contentType: file.type,
      name: file.name,
      parentId,
      size: file.size,
    }),
    contentType: file.type || undefined,
    handleUploadUrl: '/app/api/library/upload',
    multipart: file.size > 5 * 1024 * 1024,
  });
  onProgress(100);
}

function uploadThroughServer(
  file: File,
  parentId: string | null,
  onProgress: (progress: number) => void,
): Promise<void> {
  return new Promise((resolve, reject) => {
    const form = new FormData();
    form.append('file', file);
    if (parentId) {
      form.append('parentId', parentId);
    }
    const request = new XMLHttpRequest();
    request.open('POST', '/app/api/files/upload');
    request.upload.onprogress = (event) => {
      if (event.lengthComputable) {
        onProgress((event.loaded / event.total) * 100);
      }
    };
    request.onload = () => {
      if (request.status >= 200 && request.status < 300) {
        resolve();
        return;
      }
      try {
        reject(new Error(JSON.parse(request.responseText).error));
      } catch {
        reject(new Error('Upload failed'));
      }
    };
    request.onerror = () => reject(new Error('Upload failed'));
    request.send(form);
  });
}
