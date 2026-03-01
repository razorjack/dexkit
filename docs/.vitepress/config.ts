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
      { text: 'Event', link: '/event/' }
    ],
    sidebar: [
      {
        text: 'Guide',
        collapsed: false,
        items: [
          { text: 'Introduction', link: '/guide/introduction' },
          { text: 'Installation', link: '/guide/installation' },
          { text: 'Getting Started', link: '/guide/getting-started' }
        ]
      },
      {
        text: 'Operation',
        collapsed: false,
        items: [
          { text: 'Overview', link: '/operation/' },
          { text: 'Properties & Types', link: '/operation/properties' },
          { text: 'Error Handling', link: '/operation/errors' },
          { text: 'Callbacks', link: '/operation/callbacks' },
          { text: 'Transactions', link: '/operation/transactions' },
          { text: 'Advisory Locking', link: '/operation/advisory-lock' },
          { text: 'Async', link: '/operation/async' },
          { text: 'Recording', link: '/operation/recording' },
          { text: 'Safe Mode (Ok / Err)', link: '/operation/safe-mode' },
          { text: 'Pipeline & Steps', link: '/operation/pipeline' },
          { text: 'Contracts', link: '/operation/contracts' },
          { text: 'Testing', link: '/operation/testing' }
        ]
      },
      {
        text: 'Form',
        collapsed: true,
        items: [{ text: 'Dex::Form', link: '/form/' }]
      },
      {
        text: 'Event',
        collapsed: true,
        items: [{ text: 'Dex::Event', link: '/event/' }]
      }
    ],
    socialLinks: [{ icon: 'github', link: 'https://github.com/razorjack/dexkit' }]
  }
})
