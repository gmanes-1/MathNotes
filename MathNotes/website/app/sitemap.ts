import type { MetadataRoute } from 'next'
import { site } from '@/lib/site'

export const dynamic = 'force-static'

export default function sitemap(): MetadataRoute.Sitemap {
  const policyUpdated = new Date(`${site.policyUpdated}T00:00:00Z`)
  return ['/', '/prototypes/', '/privacy/', '/support/'].map((path) => ({
    url: `${site.url}${path}`,
    ...(path === '/privacy/' ? { lastModified: policyUpdated } : {}),
  }))
}
