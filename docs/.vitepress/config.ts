import { defineConfig } from 'vitepress'

export default defineConfig({
  title: 'dexkit',
  description: 'A toolkit of patterns for Ruby applications.',
  appearance: 'dark',
  themeConfig: {
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
    socialLinks: [{ icon: 'github', link: 'https://github.com/razorjack/dexkit' }]
  }
})
