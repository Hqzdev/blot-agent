import type { WebSearchResponse } from '@teya/contracts';
import { z } from 'zod';

const serperResponseSchema = z.object({
  organic: z
    .array(
      z.object({
        link: z.string().url(),
        snippet: z.string().default(''),
        title: z.string(),
      }),
    )
    .default([]),
});

const unsplashResponseSchema = z.object({
  results: z
    .array(
      z.object({
        alt_description: z.string().nullable().optional(),
        description: z.string().nullable().optional(),
        urls: z.object({
          regular: z.string().url().optional(),
          small: z.string().url().optional(),
          thumb: z.string().url().optional(),
        }),
      }),
    )
    .default([]),
});

const youtubeResponseSchema = z.object({
  items: z
    .array(
      z.object({
        id: z.object({ videoId: z.string() }),
        snippet: z.object({ title: z.string() }),
      }),
    )
    .default([]),
});

export interface SearchClient {
  search(query: string): Promise<WebSearchResponse['results']>;
}

export interface ImageSearchClient {
  search(query: string, count: number): Promise<WebSearchResponse['images']>;
}

export interface VideoSearchClient {
  search(query: string, count: number): Promise<WebSearchResponse['videos']>;
}

export class SerperSearchClient implements SearchClient {
  constructor(private readonly apiKey: string) {}

  async search(query: string): Promise<WebSearchResponse['results']> {
    const response = await fetch('https://google.serper.dev/search', {
      body: JSON.stringify({ q: query }),
      headers: {
        'content-type': 'application/json',
        'x-api-key': this.apiKey,
      },
      method: 'POST',
    });
    if (!response.ok) {
      throw new Error(`Serper search failed with ${response.status}`);
    }
    return serperResponseSchema
      .parse(await response.json())
      .organic.map((item) => ({
        snippet: item.snippet,
        title: item.title,
        url: item.link,
      }));
  }
}

export class UnsplashImageSearchClient implements ImageSearchClient {
  constructor(private readonly accessKey: string) {}

  async search(
    query: string,
    count: number,
  ): Promise<WebSearchResponse['images']> {
    const url = new URL('https://api.unsplash.com/search/photos');
    url.searchParams.set('query', query);
    url.searchParams.set('per_page', count.toString());
    const response = await fetch(url, {
      headers: {
        authorization: `Client-ID ${this.accessKey}`,
      },
    });
    if (!response.ok) {
      throw new Error(`Unsplash search failed with ${response.status}`);
    }
    return unsplashResponseSchema
      .parse(await response.json())
      .results.flatMap((image) => {
        const urlValue =
          image.urls.regular ?? image.urls.small ?? image.urls.thumb;
        return urlValue
          ? [
              {
                alt:
                  image.alt_description ?? image.description ?? 'Image result',
                url: urlValue,
              },
            ]
          : [];
      });
  }
}

export class YouTubeVideoSearchClient implements VideoSearchClient {
  constructor(private readonly apiKey: string) {}

  async search(
    query: string,
    count: number,
  ): Promise<WebSearchResponse['videos']> {
    const url = new URL('https://www.googleapis.com/youtube/v3/search');
    url.searchParams.set('part', 'snippet');
    url.searchParams.set('type', 'video');
    url.searchParams.set('q', query);
    url.searchParams.set('maxResults', count.toString());
    url.searchParams.set('key', this.apiKey);
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`YouTube search failed with ${response.status}`);
    }
    return youtubeResponseSchema
      .parse(await response.json())
      .items.map((item) => ({
        title: item.snippet.title,
        url: `https://www.youtube.com/watch?v=${item.id.videoId}`,
      }));
  }
}

export class SearchResultFormatter {
  format(input: Omit<WebSearchResponse, 'formatted'>): string {
    const sections: string[] = [];
    if (input.results.length > 0) {
      const results = input.results.map(
        (result, index) =>
          `${index + 1}. [${this.escapeText(result.title)}](${result.url}) — ${this.escapeText(result.snippet)}`,
      );
      sections.push(`### Результаты поиска\n${results.join('\n')}`);
    }
    if (input.images.length > 0) {
      const images = input.images.map(
        (image) => `![${this.escapeText(image.alt ?? 'image')}](${image.url})`,
      );
      sections.push(`### Изображения\n${images.join(' ')}`);
    }
    if (input.videos.length > 0) {
      const videos = input.videos.map(
        (video) => `[${this.escapeText(video.title)}](${video.url})`,
      );
      sections.push(`### Видео\n${videos.join('\n')}`);
    }
    return sections.join('\n\n');
  }

  private escapeText(value: string): string {
    return value.replace(/[\\[\]()*_`<>]/g, '\\$&');
  }
}

export class WebSearchService {
  constructor(
    private readonly searchClient: SearchClient,
    private readonly imageClient: ImageSearchClient,
    private readonly videoClient: VideoSearchClient,
    private readonly formatter: SearchResultFormatter,
  ) {}

  async search(query: string): Promise<WebSearchResponse> {
    const [results, images, videos] = await Promise.all([
      this.searchClient.search(query),
      this.imageClient.search(query, 4),
      this.videoClient.search(query, 2),
    ]);
    return {
      formatted: this.formatter.format({ images, results, videos }),
      images,
      results,
      videos,
    };
  }
}

export class WebSearchServiceFactory {
  create(environment: NodeJS.ProcessEnv): WebSearchService {
    const serperKey = environment.SERPER_API_KEY;
    const unsplashKey = environment.UNSPLASH_ACCESS_KEY;
    const youtubeKey = environment.YOUTUBE_API_KEY;
    if (!serperKey || !unsplashKey || !youtubeKey) {
      throw new Error(
        'SERPER_API_KEY, UNSPLASH_ACCESS_KEY and YOUTUBE_API_KEY are required',
      );
    }
    return new WebSearchService(
      new SerperSearchClient(serperKey),
      new UnsplashImageSearchClient(unsplashKey),
      new YouTubeVideoSearchClient(youtubeKey),
      new SearchResultFormatter(),
    );
  }
}
