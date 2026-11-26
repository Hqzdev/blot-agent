'use client';

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
import { SearchResultImage } from '@/lib/types';
import { PlusCircle } from 'lucide-react';
import Image from 'next/image';
import { useEffect, useState } from 'react';

interface SearchResultsImageSectionProps {
  images: SearchResultImage[];
  query?: string;
}

export const SearchResultsImageSection: React.FC<
  SearchResultsImageSectionProps
> = ({ images, query }) => {
  const [api, setApi] = useState<CarouselApi>();
  const [current, setCurrent] = useState(0);
  const [count, setCount] = useState(0);
  const [selectedIndex, setSelectedIndex] = useState(0);

  useEffect(() => {
    if (!api) return;

    setCount(api.scrollSnapList().length);
    setCurrent(api.selectedScrollSnap() + 1);

    api.on('select', () => {
      setCurrent(api.selectedScrollSnap() + 1);
    });
  }, [api]);

  useEffect(() => {
    if (api) {
      api.scrollTo(selectedIndex, true);
    }
  }, [api, selectedIndex]);

  if (!images || images.length === 0) {
    return <div className="text-sm text-[#8f8f8f]">No images found</div>;
  }

  const convertedImages =
    typeof images[0] === 'string'
      ? (images as string[]).map((image) => ({ url: image, description: '' }))
      : (images as { url: string; description: string }[]);

  return (
    <div className="grid grid-cols-2 gap-2 md:grid-cols-4">
      {convertedImages.slice(0, 4).map((image, index) => (
        <Dialog key={image.url}>
          <DialogTrigger asChild>
            <div
              className="group relative aspect-video cursor-pointer"
              onClick={() => setSelectedIndex(index)}
            >
              <Card className="h-full overflow-hidden rounded-[10px] border-[#0000001a] bg-[#f9f9f9] shadow-none">
                <CardContent className="relative size-full p-0">
                  {image ? (
                    <Image
                      src={image.url}
                      alt={`Image ${index + 1}`}
                      fill
                      className="object-cover"
                      sizes="(max-width: 768px) 50vw, 25vw"
                      unoptimized={
                        image.url.startsWith('data:') ||
                        !image.url.startsWith('http')
                      }
                    />
                  ) : (
                    <div className="size-full animate-pulse bg-[#f1f1f1]" />
                  )}
                </CardContent>
              </Card>
              {index === 3 && images.length > 4 && (
                <div className="absolute inset-0 flex items-center justify-center rounded-[10px] bg-black/50 text-sm text-white">
                  <PlusCircle size={24} />
                </div>
              )}
            </div>
          </DialogTrigger>
          <DialogContent className="max-h-[80vh] overflow-auto rounded-[10px] border-[#0000001a] bg-white text-[#0d0d0d] shadow-none sm:max-w-3xl">
            <DialogHeader>
              <DialogTitle className="text-xl font-medium">
                Search Images
              </DialogTitle>
              <DialogDescription className="text-sm text-[#5d5d5d]">
                {query}
              </DialogDescription>
            </DialogHeader>
            <div className="py-4">
              <Carousel
                setApi={setApi}
                className="w-full rounded-[10px] border border-[#0000001a] bg-[#f9f9f9]"
              >
                <CarouselContent>
                  {convertedImages.map((img, idx) => (
                    <CarouselItem key={img.url}>
                      <div className="relative flex h-[60vh] w-full items-center justify-center p-1">
                        <Image
                          src={img.url}
                          alt={`Image ${idx + 1}`}
                          fill
                          className="object-contain"
                          sizes="(max-width: 768px) 100vw, 80vw"
                          onError={(e) => {
                            const target = e.target as HTMLImageElement;
                            target.src = '/images/placeholder-image.png';
                          }}
                        />
                      </div>
                    </CarouselItem>
                  ))}
                </CarouselContent>
                <div className="absolute inset-8 flex items-center justify-between p-4">
                  <CarouselPrevious className="size-9 rounded-[10px] border-[#0000001a] bg-white text-[#0d0d0d] shadow-none focus:outline-none">
                    <span className="sr-only">Previous</span>
                  </CarouselPrevious>
                  <CarouselNext className="size-9 rounded-[10px] border-[#0000001a] bg-white text-[#0d0d0d] shadow-none focus:outline-none">
                    <span className="sr-only">Next</span>
                  </CarouselNext>
                </div>
              </Carousel>
              <div className="py-2 text-center text-sm text-[#8f8f8f]">
                {current} of {count}
              </div>
            </div>
          </DialogContent>
        </Dialog>
      ))}
    </div>
  );
};
