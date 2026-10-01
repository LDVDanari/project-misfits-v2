import { allStoreItems } from '../lib/products';
export default function sitemap() {
  const base = process.env.NEXT_PUBLIC_SITE_URL || 'https://yourdomain.com';
  const staticRoutes = ['', '/store', '/city-info', '/rules'];
  return [
    ...staticRoutes.map(route => ({ url: `${base}${route}`, changeFrequency: 'weekly', priority: route === '' ? 1 : .8 })),
    ...allStoreItems.map(p => ({ url: `${base}/store/${p.slug}`, changeFrequency: 'weekly', priority: .7 })),
  ];
}
