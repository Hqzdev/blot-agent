'use client';

import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { SearchResultItem } from '@/lib/types';
import { ChevronDown, ChevronUp, Youtube } from 'lucide-react';
import Image from 'next/image';
import Link from 'next/link';
import { useState } from 'react';

export interface SearchResultsProps {
  results: SearchResultItem[];
}

export function SearchResults({ results }: SearchResultsProps) {
  const [isExpanded, setIsExpanded] = useState(false);

  const displayedResults = isExpanded ? results : results.slice(0, 4);
  const hasMoreResults = results.length > 4;

  const displayUrlName = (url: string) => {
    try {
      const hostname = new URL(url).hostname;
      return hostname === 'www.youtube.com' ? 'YouTube' : hostname;
    } catch {
      return url;
    }
  };

  const getYouTubeThumbnail = (url: string): string | undefined => {
    try {
      const urlObj = new URL(url);
      const videoId = urlObj.searchParams.get('v');
      return videoId
        ? `https://img.youtube.com/vi/${videoId}/mqdefault.jpg`
        : undefined;
    } catch {
      return undefined;
    }
  };

  const isYouTubeUrl = (url: string) => {
    try {
      return new URL(url).hostname.includes('youtube.com');
    } catch {
      return false;
    }
  };

  return (
    <div className="space-y-2">
      <div className="grid grid-cols-1 gap-2">
        {displayedResults.map((result, index) => {
          const thumbnail = isYouTubeUrl(result.url)
            ? getYouTubeThumbnail(result.url)
            : undefined;

          return (
            <Link
              key={index}
              href={result.url}
              target="_blank"
              className="block rounded-[10px] outline-none focus-visible:ring-1 focus-visible:ring-[#0d0d0d]"
            >
              <Card className="overflow-hidden rounded-[10px] border-[#0000001a] bg-white shadow-none transition-colors hover:bg-[#0000000d]">
                <CardContent className="p-0">
                  <div className="flex gap-3 p-3">
                    <div className="relative aspect-video w-28 shrink-0 overflow-hidden rounded-lg border border-[#0000000d] bg-[#f9f9f9] sm:w-36">
                      {thumbnail ? (
                        <Image
                          src={thumbnail}
                          alt={result.title || ''}
                          width={192}
                          height={108}
                          className="size-full object-cover"
                        />
                      ) : (
                        <div className="flex size-full items-center justify-center">
                          <Youtube className="size-6 text-[#8f8f8f]" />
                        </div>
                      )}
                    </div>
                    <div className="flex min-w-0 flex-col justify-between py-0.5">
                      <div>
                        <h3 className="line-clamp-2 text-sm font-medium leading-5 text-[#0d0d0d]">
                          {result.title}
                        </h3>
                        <p className="mt-1 line-clamp-2 text-xs leading-4 text-[#5d5d5d]">
                          {result.content}
                        </p>
                      </div>
                      <div className="mt-2 flex items-center gap-2">
                        <Avatar className="size-4">
                          <AvatarImage
                            src={`https://www.google.com/s2/favicons?domain=${result.url}`}
                            alt={displayUrlName(result.url)}
                          />
                          <AvatarFallback>
                            {displayUrlName(result.url)[0]}
                          </AvatarFallback>
                        </Avatar>
                        <span className="truncate text-xs text-[#8f8f8f]">
                          {displayUrlName(result.url)}
                        </span>
                      </div>
                    </div>
                  </div>
                </CardContent>
              </Card>
            </Link>
          );
        })}
      </div>
      {hasMoreResults && (
        <Button
          variant="outline"
          className="h-9 w-full rounded-[10px] border-[#0000001a] bg-white text-sm text-[#0d0d0d] shadow-none hover:bg-[#0000000d] hover:text-[#0d0d0d]"
          onClick={() => setIsExpanded(!isExpanded)}
        >
          {isExpanded ? (
            <>
              Show Less <ChevronUp className="ml-2 size-4" />
            </>
          ) : (
            <>
              Show More <ChevronDown className="ml-2 size-4" />
            </>
          )}
        </Button>
      )}
    </div>
  );
}
