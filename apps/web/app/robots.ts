import type { MetadataRoute } from 'next';

export default function robots(): MetadataRoute.Robots {
  const baseUrl = `${process.env.AUTH_URL || 'http://127.0.0.1:3001'}/app`;

  return {
    rules: [
      {
        userAgent: '*',
        allow: '/app/',
        disallow: ['/app/api/', '/app/chat/', '/app/_next/', '/app/admin/'],
      },
    ],
    sitemap: `${baseUrl}/sitemap.xml`,
  };
}
