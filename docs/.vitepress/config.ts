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
          { text: 'Defining Operations', link: '/operation/defining-operations' },
          { text: 'Parameters', link: '/operation/parameters' },
          { text: 'Pipeline & Steps', link: '/operation/pipeline' },
          { text: 'Callbacks', link: '/operation/callbacks' },
          { text: 'Error Handling', link: '/operation/errors' },
          { text: 'Async', link: '/operation/async' },
          { text: 'Transactions', link: '/operation/transactions' },
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
