import type { Metadata, Viewport } from 'next'
import type { ReactNode } from 'react'
import '@fontsource-variable/fraunces/full.css'
import '@fontsource-variable/archivo/wdth.css'
import '@fontsource-variable/bricolage-grotesque/wdth.css'
import './globals.css'
import { Providers } from '@/components/Providers'
import { SiteFooter } from '@/components/SiteFooter'
import { SiteNav } from '@/components/SiteNav'
import { site } from '@/lib/site'

export const metadata: Metadata = {
  metadataBase: new URL(`${site.url}/`),
  title: { default: 'OwlLuna: handwritten notes for iPad, free and open source', template: '%s · OwlLuna' },
  description: site.description,
  applicationName: site.name,
  authors: [{ name: site.author.name, url: site.author.url }],
  openGraph: {
    type: 'website',
    siteName: site.name,
    url: './',
    images: [
      {
        url: '/opengraph-image.png',
        width: 1200,
        height: 630,
        type: 'image/png',
        alt: 'OwlLuna: an owl writing on a notepad beside the words Handwritten notes for iPad. Free, for good.',
      },
    ],
  },
  twitter: { card: 'summary_large_image' },
}

export const viewport: Viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#f1ede4' },
    { media: '(prefers-color-scheme: dark)', color: '#181613' },
  ],
}

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="en" data-scroll-behavior="smooth">
      <body>
        <a href="#main" className="skip-link">
          Skip to content
        </a>
        <Providers>
          <SiteNav />
          <main id="main">{children}</main>
          <SiteFooter />
        </Providers>
      </body>
    </html>
  )
}
