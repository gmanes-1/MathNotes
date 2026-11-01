const basePath = process.env.BASE_PATH ?? ''

/** @type {import('next').NextConfig} */
const config = {
  output: 'export',
  trailingSlash: true,
  basePath: basePath || undefined,
  images: { unoptimized: true },
  agentRules: false,
  env: { NEXT_PUBLIC_BASE_PATH: basePath },
}

export default config
