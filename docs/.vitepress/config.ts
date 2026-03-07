import { writeFile } from 'node:fs/promises'
import { join } from 'node:path'
import { defineConfig, type HeadConfig, type PageData } from 'vitepress'

const SITE_URL = 'https://dex.razorjack.net/'
const SITE_NAME = 'dexkit'
const SITE_DESCRIPTION =
  'Documentation for dexkit, a Ruby toolkit for operations, events, forms, and queries in Rails applications.'

const SECTION_TITLES: Record<string, string> = {
  guide: 'Guide',
  operation: 'Dex::Operation',
  form: 'Dex::Form',
  event: 'Dex::Event',
  query: 'Dex::Query'
}

const SECTION_ENTRY_PATHS: Record<string, string> = {
  guide: '/guide/introduction.html',
  operation: '/operation/',
  form: '/form/',
  event: '/event/',
  query: '/query/'
}

function sectionFor(relativePath: string): string | null {
  const [section] = relativePath.split('/')
  return SECTION_TITLES[section] ? section : null
}

function pagePathFor(relativePath: string): string {
  if (!relativePath || relativePath === 'index.md') return '/'
  if (relativePath.endsWith('/index.md')) return `/${relativePath.replace(/index\.md$/, '')}`

  return `/${relativePath.replace(/\.md$/, '.html')}`
}

function canonicalUrlFor(relativePath: string): string {
  return new URL(pagePathFor(relativePath), SITE_URL).toString()
}

function normalizeSitemapUrl(url: string): string {
  if (!url) return '/'
  if (url.startsWith('http://') || url.startsWith('https://')) {
    return new URL(url).pathname || '/'
  }

  return url.startsWith('/') ? url : `/${url}`
}

function sitemapPriorityFor(url: string): number {
  const normalizedUrl = normalizeSitemapUrl(url)

  if (normalizedUrl === '/') return 1.0
  if (Object.values(SECTION_ENTRY_PATHS).includes(normalizedUrl)) return 0.9
  return 0.7
}

function sitemapChangefreqFor(url: string): 'weekly' | 'monthly' {
  const normalizedUrl = normalizeSitemapUrl(url)

  if (normalizedUrl === '/' || Object.values(SECTION_ENTRY_PATHS).includes(normalizedUrl)) return 'weekly'
  return 'monthly'
}

function structuredDataFor(pageData: PageData, description: string): object[] {
  const relativePath = pageData.relativePath
  const url = canonicalUrlFor(relativePath)
  const title = pageData.title || SITE_NAME

  if (relativePath === 'index.md') {
    return [
      {
        '@context': 'https://schema.org',
        '@type': 'WebSite',
        name: SITE_NAME,
        url: SITE_URL,
        description,
        inLanguage: 'en-US',
        publisher: {
          '@type': 'Organization',
          name: SITE_NAME,
          url: SITE_URL
        }
      }
    ]
  }

  const section = sectionFor(relativePath)
  const breadcrumbItems = [
    {
      '@type': 'ListItem',
      position: 1,
      name: SITE_NAME,
      item: SITE_URL
    }
  ]

  if (section) {
    const sectionUrl = new URL(SECTION_ENTRY_PATHS[section], SITE_URL).toString()

    if (sectionUrl !== url) {
      breadcrumbItems.push({
        '@type': 'ListItem',
        position: 2,
        name: SECTION_TITLES[section],
        item: sectionUrl
      })
    }
  }

  breadcrumbItems.push({
    '@type': 'ListItem',
    position: breadcrumbItems.length + 1,
    name: title,
    item: url
  })

  const article: Record<string, string> = {
    '@context': 'https://schema.org',
    '@type': 'TechArticle',
    headline: title,
    description,
    url,
    mainEntityOfPage: url,
    isPartOf: SITE_URL,
    inLanguage: 'en-US'
  }

  if (section) {
    article.articleSection = SECTION_TITLES[section]
  }

  if (pageData.lastUpdated) {
    article.dateModified = new Date(pageData.lastUpdated).toISOString()
  }

  return [
    article,
    {
      '@context': 'https://schema.org',
      '@type': 'BreadcrumbList',
      itemListElement: breadcrumbItems
    }
  ]
}

export default defineConfig({
  lang: 'en-US',
  title: 'dexkit',
  description: SITE_DESCRIPTION,
  appearance: 'dark',
  srcExclude: ['**/AGENTS.md', '**/CLAUDE.md'],
  lastUpdated: true,
  head: [
    ['meta', { name: 'application-name', content: SITE_NAME }],
    ['meta', { name: 'theme-color', content: '#111827' }],
    ['meta', { property: 'og:site_name', content: SITE_NAME }],
    ['meta', { property: 'og:locale', content: 'en_US' }]
  ],
  sitemap: {
    hostname: SITE_URL,
    async transformItems(items) {
      return items
        .filter((item) => !normalizeSitemapUrl(item.url).startsWith('/404'))
        .map((item) => ({
          ...item,
          changefreq: sitemapChangefreqFor(item.url),
          priority: sitemapPriorityFor(item.url)
        }))
    }
  },
  transformHead({ pageData, title, description }) {
    if (pageData.isNotFound || pageData.relativePath === '404.md') {
      return [
        ['meta', { name: 'robots', content: 'noindex,nofollow' }],
        ['meta', { name: 'googlebot', content: 'noindex,nofollow' }]
      ] satisfies HeadConfig[]
    }

    const canonicalUrl = canonicalUrlFor(pageData.relativePath)
    const metaDescription = description || SITE_DESCRIPTION
    const head: HeadConfig[] = [
      ['link', { rel: 'canonical', href: canonicalUrl }],
      [
        'meta',
        {
          name: 'robots',
          content: 'index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1'
        }
      ],
      [
        'meta',
        {
          name: 'googlebot',
          content: 'index,follow,max-image-preview:large,max-snippet:-1,max-video-preview:-1'
        }
      ],
      ['meta', { property: 'og:type', content: pageData.relativePath === 'index.md' ? 'website' : 'article' }],
      ['meta', { property: 'og:title', content: title }],
      ['meta', { property: 'og:description', content: metaDescription }],
      ['meta', { property: 'og:url', content: canonicalUrl }],
      ['meta', { name: 'twitter:card', content: 'summary' }],
      ['meta', { name: 'twitter:title', content: title }],
      ['meta', { name: 'twitter:description', content: metaDescription }],
      ['script', { type: 'application/ld+json' }, JSON.stringify(structuredDataFor(pageData, metaDescription))]
    ]

    const section = sectionFor(pageData.relativePath)
    if (section) {
      head.push(['meta', { property: 'article:section', content: SECTION_TITLES[section] }])
    }

    if (pageData.lastUpdated && pageData.relativePath !== 'index.md') {
      head.push([
        'meta',
        {
          property: 'article:modified_time',
          content: new Date(pageData.lastUpdated).toISOString()
        }
      ])
    }

    return head
  },
  async buildEnd(siteConfig) {
    const robots = ['User-agent: *', 'Allow: /', '', `Sitemap: ${new URL('sitemap.xml', SITE_URL).toString()}`, ''].join('\n')
    await writeFile(join(siteConfig.outDir, 'robots.txt'), robots)
  },
  markdown: {
    theme: {
      light: 'catppuccin-latte',
      dark: 'ayu-dark'
    }
  },
  themeConfig: {
    lastUpdated: { text: 'Last updated' },
    nav: [
      { text: 'Guide', link: '/guide/introduction' },
      { text: 'Operation', link: '/operation/' },
      { text: 'Form', link: '/form/' },
      { text: 'Event', link: '/event/' },
      { text: 'Query', link: '/query/' }
    ],
    sidebar: [
      {
        text: 'Guide',
        collapsed: false,
        items: [
          { text: 'Introduction', link: '/guide/introduction' },
          { text: 'Installation', link: '/guide/installation' },
          { text: 'DX Meets AI', link: '/guide/philosophy' }
        ]
      },
      {
        text: 'Operation',
        collapsed: false,
        items: [
          { text: 'Overview', link: '/operation/' },
          { text: 'Properties & Types', link: '/operation/properties' },
          { text: 'Error Handling', link: '/operation/errors' },
          { text: 'Ok / Err', link: '/operation/safe-mode' },
          { text: 'Callbacks', link: '/operation/callbacks' },
          { text: 'Transactions', link: '/operation/transactions' },
          { text: 'Idempotency', link: '/operation/once' },
          { text: 'Advisory Locking', link: '/operation/advisory-lock' },
          { text: 'Async', link: '/operation/async' },
          { text: 'Recording', link: '/operation/recording' },
          { text: 'Middleware', link: '/operation/pipeline' },
          { text: 'Contracts', link: '/operation/contracts' },
          { text: 'Testing', link: '/operation/testing' }
        ]
      },
      {
        text: 'Form',
        collapsed: false,
        items: [
          { text: 'Overview', link: '/form/' },
          { text: 'Attributes & Normalization', link: '/form/attributes' },
          { text: 'Validation', link: '/form/validation' },
          { text: 'Nested Forms', link: '/form/nesting' },
          { text: 'Rails Integration', link: '/form/rails' },
          { text: 'Conventions', link: '/form/conventions' }
        ]
      },
      {
        text: 'Event',
        collapsed: false,
        items: [
          { text: 'Overview', link: '/event/' },
          { text: 'Publishing', link: '/event/publishing' },
          { text: 'Handling', link: '/event/handling' },
          { text: 'Tracing & Suppression', link: '/event/tracing' },
          { text: 'Testing', link: '/event/testing' }
        ]
      },
      {
        text: 'Query',
        collapsed: false,
        items: [
          { text: 'Overview', link: '/query/' },
          { text: 'Filtering', link: '/query/filtering' },
          { text: 'Sorting', link: '/query/sorting' },
          { text: 'Rails Integration', link: '/query/rails' },
          { text: 'Testing', link: '/query/testing' }
        ]
      }
    ],
    footer: {
      message: 'Released under the MIT License.',
      copyright: 'Made by <a href="https://razorjack.net">Jacek Galanciak</a>'
    },
    socialLinks: [{ icon: 'github', link: 'https://github.com/razorjack/dexkit' }]
  }
})
