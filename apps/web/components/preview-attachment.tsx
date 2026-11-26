import type { Attachment } from 'ai';
import Image from 'next/image';

import { LoaderIcon } from './icons';

export const PreviewAttachment = ({
  attachment,
  isUploading = false,
}: {
  attachment: Attachment;
  isUploading?: boolean;
}) => {
  const { name, url, contentType } = attachment;
  const deleted =
    typeof attachment === 'object' &&
    attachment !== null &&
    'deleted' in attachment &&
    attachment.deleted === true;

  return (
    <div
      data-testid="input-attachment-preview"
      className="flex w-[76px] flex-col gap-1.5"
    >
      <div className="relative size-[76px] overflow-hidden rounded-[10px] border border-[var(--chat-hairline)] bg-[var(--chat-sidebar-mist)]">
        {deleted ? (
          <div className="flex h-full items-center justify-center px-2 text-center text-[10px] font-medium text-[var(--chat-hollow)]">
            File deleted
          </div>
        ) : contentType ? (
          contentType.startsWith('image') ? (
            <Image
              key={url}
              src={url}
              alt={name ?? 'An image attachment'}
              fill
              className="object-cover"
              sizes="76px"
              unoptimized={url.startsWith('data:') || url.startsWith('blob:')}
            />
          ) : (
            <div className="" />
          )
        ) : (
          <div className="" />
        )}

        {isUploading && (
          <div
            data-testid="input-attachment-loader"
            className="absolute inset-0 flex items-center justify-center bg-[var(--chat-paper)]/70 text-[var(--chat-mid-ash)] [&>svg]:animate-spin"
          >
            <LoaderIcon />
          </div>
        )}
      </div>
      <div className="truncate text-xs text-[var(--chat-hollow)]">{name}</div>
    </div>
  );
};
