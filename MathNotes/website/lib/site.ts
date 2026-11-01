const repo = 'https://github.com/owaisazmal/OwlLuna'

export const site = {
  name: 'OwlLuna',
  description:
    'A free, open-source handwritten notes app for iPad. No subscriptions, no ads, no accounts and no tracking.',
  url: process.env.NEXT_PUBLIC_SITE_URL ?? 'https://owaisazmal.github.io/OwlLuna',
  repo,
  issues: `${repo}/issues`,
  newIssue: `${repo}/issues/new`,
  license: `${repo}/blob/main/LICENSE`,
  fontLicenses: `${repo}/tree/main/OwlLuna/Resources/Fonts`,
  contributing: `${repo}/blob/main/CONTRIBUTING.md`,
  author: { name: 'Owais Khan', url: 'https://github.com/owaisazmal' },
  /** Who designed the owl of the app's icon. */
  logoDesigner: { name: 'Safiya Sulaiman', url: 'https://www.linkedin.com/in/safiya-sulaiman-53920932a/' },
  /** The years in the footer's copyright line, as in LICENSE. */
  since: '2024–2026',
  /** The App Store page, once the app is published. Empty until then. */
  appStoreUrl: '',
  /** An address for privacy and support questions. Empty shows GitHub Issues alone. */
  contactEmail: '',
  /** The day the privacy policy last changed, as YYYY-MM-DD. */
  policyUpdated: '2026-10-12',
}

const basePath = process.env.NEXT_PUBLIC_BASE_PATH ?? ''

/** A file in `public/`, under the site's base path. */
export function asset(path: string): string {
  return `${basePath}${path.startsWith('/') ? path : `/${path}`}`
}

export function formatDate(iso: string): string {
  const [year, month, day] = iso.split('-').map(Number)
  return new Date(Date.UTC(year, month - 1, day)).toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
    timeZone: 'UTC',
  })
}
