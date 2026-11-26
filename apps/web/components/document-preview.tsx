'use client';

import { useArtifact } from '@/hooks/use-artifact';
import { Document } from '@/lib/db/schema';
import { cn, fetcher } from '@/lib/utils';
import equal from 'fast-deep-equal';
import dynamic from 'next/dynamic';
import {
  MouseEvent,
  memo,
  useCallback,
  useEffect,
  useMemo,
  useRef,
} from 'react';
import useSWR from 'swr';
import { ArtifactKind, UIArtifact } from './artifact';
import { DocumentToolCall, DocumentToolResult } from './document';
import { InlineDocumentSkeleton } from './document-skeleton';
import { FullscreenIcon, ImageIcon, LoaderIcon } from './icons';

const Editor = dynamic(
  () => import('./text-editor').then((mod) => ({ default: mod.Editor })),
  {
    ssr: false,
    loading: () => (
      <div className="h-32 animate-pulse rounded-[10px] bg-[#f1f1f1]" />
    ),
  },
);

const CodeEditor = dynamic(
  () => import('./code-editor').then((mod) => ({ default: mod.CodeEditor })),
  {
    ssr: false,
    loading: () => (
      <div className="h-32 animate-pulse rounded-[10px] bg-[#f1f1f1]" />
    ),
  },
);

const SpreadsheetEditor = dynamic(
  () =>
    import('./sheet-editor').then((mod) => ({
      default: mod.SpreadsheetEditor,
    })),
  {
    ssr: false,
    loading: () => (
      <div className="h-32 animate-pulse rounded-[10px] bg-[#f1f1f1]" />
    ),
  },
);

const ImageEditor = dynamic(
  () => import('./image-editor').then((mod) => ({ default: mod.ImageEditor })),
  {
    ssr: false,
    loading: () => (
      <div className="h-32 animate-pulse rounded-[10px] bg-[#f1f1f1]" />
    ),
  },
);

interface DocumentPreviewProps {
  isReadonly: boolean;
  result?: any;
  args?: any;
}

export function DocumentPreview({
  isReadonly,
  result,
  args,
}: DocumentPreviewProps) {
  const { artifact, setArtifact } = useArtifact();

  const { data: documents, isLoading: isDocumentsFetching } = useSWR<
    Array<Document>
  >(result ? `/app/api/document?id=${result.id}` : null, fetcher);

  const previewDocument = useMemo(() => documents?.[0], [documents]);
  const hitboxRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const boundingBox = hitboxRef.current?.getBoundingClientRect();

    if (artifact.documentId && boundingBox) {
      setArtifact((artifact) => ({
        ...artifact,
        boundingBox: {
          left: boundingBox.x,
          top: boundingBox.y,
          width: boundingBox.width,
          height: boundingBox.height,
        },
      }));
    }
  }, [artifact.documentId, setArtifact]);

  if (artifact.isVisible) {
    if (result) {
      return (
        <DocumentToolResult
          type="create"
          result={{ id: result.id, title: result.title, kind: result.kind }}
          isReadonly={isReadonly}
        />
      );
    }

    if (args) {
      return (
        <DocumentToolCall
          type="create"
          args={{ title: args.title }}
          isReadonly={isReadonly}
        />
      );
    }
  }

  if (isDocumentsFetching) {
    return <LoadingSkeleton artifactKind={result.kind ?? args.kind} />;
  }

  const document: Document | null = previewDocument
    ? previewDocument
    : artifact.status === 'streaming'
      ? {
          title: artifact.title,
          text: artifact.kind,
          content: artifact.content,
          id: artifact.documentId,
          createdAt: new Date(),
          userId: 'noop',
        }
      : null;

  if (!document) return <LoadingSkeleton artifactKind={artifact.kind} />;

  return (
    <div className="relative w-full cursor-pointer">
      <HitboxLayer
        hitboxRef={hitboxRef}
        result={result}
        setArtifact={setArtifact}
      />
      <DocumentHeader
        title={document.title}
        kind={document.text}
        isStreaming={artifact.status === 'streaming'}
      />
      <DocumentContent document={document} />
    </div>
  );
}

const LoadingSkeleton = ({ artifactKind }: { artifactKind: ArtifactKind }) => (
  <div className="w-full">
    <div className="flex h-[57px] flex-row items-center justify-between gap-2 rounded-t-[10px] border border-[#0000001a] bg-[#f9f9f9] p-4">
      <div className="flex flex-row items-center gap-3">
        <div className="text-[#8f8f8f]">
          <div className="size-4 animate-pulse rounded-md bg-[#0000001a]" />
        </div>
        <div className="h-4 w-24 animate-pulse rounded-lg bg-[#0000001a]" />
      </div>
      <div>
        <FullscreenIcon />
      </div>
    </div>
    {artifactKind === 'image' ? (
      <div className="overflow-y-scroll rounded-b-[10px] border border-t-0 border-[#0000001a] bg-[#f9f9f9]">
        <div className="h-[257px] w-full animate-pulse bg-[#0000001a]" />
      </div>
    ) : (
      <div className="overflow-y-scroll rounded-b-[10px] border border-t-0 border-[#0000001a] bg-[#f9f9f9] p-8 pt-4">
        <InlineDocumentSkeleton />
      </div>
    )}
  </div>
);

const PureHitboxLayer = ({
  hitboxRef,
  result,
  setArtifact,
}: {
  hitboxRef: React.RefObject<HTMLDivElement>;
  result: any;
  setArtifact: (
    updaterFn: UIArtifact | ((currentArtifact: UIArtifact) => UIArtifact),
  ) => void;
}) => {
  const handleClick = useCallback(
    (event: MouseEvent<HTMLElement>) => {
      const boundingBox = event.currentTarget.getBoundingClientRect();

      setArtifact((artifact) =>
        artifact.status === 'streaming'
          ? { ...artifact, isVisible: true }
          : {
              ...artifact,
              title: result.title,
              documentId: result.id,
              kind: result.kind,
              isVisible: true,
              boundingBox: {
                left: boundingBox.x,
                top: boundingBox.y,
                width: boundingBox.width,
                height: boundingBox.height,
              },
            },
      );
    },
    [setArtifact, result],
  );

  return (
    <div
      className="absolute left-0 top-0 z-10 size-full rounded-[10px]"
      ref={hitboxRef}
      onClick={handleClick}
      role="presentation"
      aria-hidden="true"
    >
      <div className="flex w-full items-center justify-end p-4">
        <div className="absolute right-[9px] top-[13px] rounded-lg p-2 hover:bg-[#0000000d]">
          <FullscreenIcon />
        </div>
      </div>
    </div>
  );
};

const HitboxLayer = memo(PureHitboxLayer, (prevProps, nextProps) => {
  if (!equal(prevProps.result, nextProps.result)) return false;
  return true;
});

const PureDocumentHeader = ({
  title,
  kind,
  isStreaming,
}: {
  title: string;
  kind: ArtifactKind;
  isStreaming: boolean;
}) => (
  <div className="flex flex-row items-start justify-between gap-2 rounded-t-[10px] border border-[#0000001a] bg-[#f9f9f9] p-4 sm:items-center">
    <div className="flex flex-row items-start gap-3 sm:items-center">
      <div className="text-[#8f8f8f]">
        {isStreaming ? (
          <div className="animate-spin">
            <LoaderIcon />
          </div>
        ) : kind === 'image' ? (
          <ImageIcon />
        ) : null}
      </div>
      <div className="-translate-y-1 font-medium sm:translate-y-0">{title}</div>
    </div>
    <div className="w-8" />
  </div>
);

const DocumentHeader = memo(PureDocumentHeader, (prevProps, nextProps) => {
  if (prevProps.title !== nextProps.title) return false;
  if (prevProps.isStreaming !== nextProps.isStreaming) return false;

  return true;
});

const DocumentContent = ({ document }: { document: Document }) => {
  const { artifact } = useArtifact();

  const containerClassName = cn(
    'h-[257px] overflow-y-scroll rounded-b-[10px] border border-t-0 border-[#0000001a] bg-white',
    {
      'p-4 sm:px-14 sm:py-16': document.text === 'text',
      'p-0': document.text === 'code',
    },
  );

  const commonProps = {
    content: document.content ?? '',
    isCurrentVersion: true,
    currentVersionIndex: 0,
    status: artifact.status,
    saveContent: () => {},
    suggestions: [],
  };

  return (
    <div className={containerClassName}>
      {document.text === 'text' ? (
        <Editor {...commonProps} onSaveContent={() => {}} />
      ) : document.text === 'code' ? (
        <div className="relative flex w-full flex-1">
          <div className="absolute inset-0">
            <CodeEditor {...commonProps} onSaveContent={() => {}} />
          </div>
        </div>
      ) : document.text === 'sheet' ? (
        <div className="relative flex size-full flex-1 p-4">
          <div className="absolute inset-0">
            <SpreadsheetEditor {...commonProps} />
          </div>
        </div>
      ) : document.text === 'image' ? (
        <ImageEditor
          title={document.title}
          content={document.content ?? ''}
          isCurrentVersion={true}
          currentVersionIndex={0}
          status={artifact.status}
          isInline={true}
        />
      ) : null}
    </div>
  );
};
