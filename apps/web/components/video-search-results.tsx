'use client';

import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { Card, CardContent } from '@/components/ui/card';
import {
  Carousel,
  type CarouselApi,
  CarouselContent,
  CarouselItem,
  CarouselNext,
  CarouselPrevious,
} from '@/components/ui/carousel';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog';
import { SerperSearchResultItem, SerperSearchResults } from '@/lib/types';
import { Play, PlusCircle } from 'lucide-react';
import Image from 'next/image';
import { useEffect, useRef, useState } from 'react';

export interface VideoSearchResultsProps {
  results: SerperSearchResults;
}

export function VideoSearchResults({ results }: VideoSearchResultsProps) {
  const [api, setApi] = useState<CarouselApi>();
  const [current, setCurrent] = useState(1);
  const [count, setCount] = useState(0);
  const [selectedIndex, setSelectedIndex] = useState(0);
  const videoRefs = useRef<(HTMLIFrameElement | null)[]>([]);

  const videos = results.videos.filter((video: SerperSearchResultItem) => {
    return new URL(video.link).pathname === '/watch';
  });

  useEffect(() => {
    if (api) {
      setCount(api.scrollSnapList().length);
      setCurrent(api.selectedScrollSnap() + 1);

      api.on('select', () => {
        const newCurrent = api.selectedScrollSnap() + 1;
        if (newCurrent !== current && videoRefs.current[current - 1]) {
          const prevVideo = videoRefs.current[current - 1];
          prevVideo?.contentWindow?.postMessage(
            '{"event":"command","func":"pauseVideo","args":""}',
            '*',
          );
        }
        setCurrent(newCurrent);
      });
    }
  }, [api, current]);

  useEffect(() => {
    if (api) {
      api.scrollTo(selectedIndex, true);
    }
  }, [api, selectedIndex]);

  if (!results.videos || results.videos.length === 0) {
    return <div className="text-sm text-[#8f8f8f]">No videos found</div>;
  }

  return (
    <div className="flex flex-wrap">
      {videos
        .slice(0, 4)
        .map((result: SerperSearchResultItem, index: number) => (
          <Dialog key={result.link}>
            <DialogTrigger asChild>
              <div
                className="relative w-1/2 cursor-pointer p-1 md:w-1/4"
                onClick={() => setSelectedIndex(index)}
              >
                <Card className="min-h-40 flex-1 rounded-[10px] border-[#0000001a] bg-white shadow-none">
                  <CardContent className="p-2.5">
                    <div className="relative mb-2 aspect-video w-full overflow-hidden rounded-lg bg-[#f1f1f1]">
                      <Image
                        src={result.imageUrl}
                        alt={result.title}
                        fill
                        className="object-cover"
                        sizes="(max-width: 768px) 50vw, 25vw"
                        unoptimized={!result.imageUrl.startsWith('http')}
                      />
                    </div>
                    <p className="line-clamp-2 text-xs text-[#0d0d0d]">
                      {result.title}
                    </p>
                    <div className="mt-2 flex items-center gap-2">
                      <Avatar className="size-4">
                        <AvatarImage
                          src={`https://www.google.com/s2/favicons?domain=${
                            new URL(result.link).hostname
                          }`}
                          alt={result.channel}
                        />
                        <AvatarFallback>
                          {new URL(result.link).hostname[0]}
                        </AvatarFallback>
                      </Avatar>
                      <div className="truncate text-xs text-[#8f8f8f]">
                        {new URL(result.link).hostname}
                      </div>
                    </div>
                    <div className="mt-2 flex items-center gap-2 text-[#5d5d5d]">
                      <Play className="size-3.5" />
                      <span className="text-xs">Watch Video</span>
                    </div>
                  </CardContent>
                </Card>
                {index === 3 && results.videos.length > 4 && (
                  <div className="absolute inset-1 flex items-center justify-center rounded-[10px] bg-black/50 text-sm text-white">
                    <PlusCircle size={24} />
                  </div>
                )}
              </div>
            </DialogTrigger>
            <DialogContent className="max-h-[80vh] overflow-auto rounded-[10px] border-[#0000001a] bg-white text-[#0d0d0d] shadow-none sm:max-w-3xl">
              <DialogHeader>
                <DialogTitle className="text-xl font-medium">
                  Search Videos
                </DialogTitle>
                <DialogDescription className="text-sm text-[#5d5d5d]">
                  {results.searchParameters.q}
                </DialogDescription>
              </DialogHeader>
              <div className="py-4">
                <Carousel
                  setApi={setApi}
                  className="max-h-[60vh] w-full overflow-hidden rounded-[10px] border border-[#0000001a] bg-[#f9f9f9]"
                >
                  <CarouselContent>
                    {videos.map((video, idx) => {
                      const videoId = video.link.split('v=')[1];
                      return (
                        <CarouselItem key={video.link}>
                          <div className="flex h-full items-center justify-center p-1">
                            <iframe
                              ref={(el) => {
                                videoRefs.current[idx] = el;
                              }}
                              src={`https://www.youtube.com/embed/${videoId}?enablejsapi=1`}
                              className="aspect-video w-full"
                              title={video.title}
                              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
                              allowFullScreen
                            />
                          </div>
                        </CarouselItem>
                      );
                    })}
                  </CarouselContent>
                  <div className="pointer-events-none absolute inset-8 flex items-center justify-between p-4">
                    <CarouselPrevious className="pointer-events-auto size-9 rounded-[10px] border-[#0000001a] bg-white text-[#0d0d0d] shadow-none focus:outline-none">
                      <span className="sr-only">Previous</span>
                    </CarouselPrevious>
                    <CarouselNext className="pointer-events-auto size-9 rounded-[10px] border-[#0000001a] bg-white text-[#0d0d0d] shadow-none focus:outline-none">
                      <span className="sr-only">Next</span>
                    </CarouselNext>
                  </div>
                </Carousel>
                <div className="py-2">
                  <div className="text-center text-sm text-[#8f8f8f]">
                    {current} of {count}
                  </div>
                </div>
              </div>
            </DialogContent>
          </Dialog>
        ))}
    </div>
  );
}
