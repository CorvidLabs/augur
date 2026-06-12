import { defineConfig } from 'astro/config'
import mdx from '@astrojs/mdx'
import sitemap from '@astrojs/sitemap'

function rewriteMdLinks() {
  return (tree) => {
    const visit = (node) => {
      if (node.type === 'link' && typeof node.url === 'string') {
        node.url = node.url.replace(/\.md(#|$)/, '$1')
      }
      if (node.children) node.children.forEach(visit)
    }
    visit(tree)
  }
}

export default defineConfig({
  site: 'https://corvidlabs.github.io',
  base: '/augur/',
  trailingSlash: 'never',
  integrations: [mdx(), sitemap()],
  markdown: {
    remarkPlugins: [rewriteMdLinks],
    shikiConfig: {
      // The css-variables theme emits --shiki-* custom properties instead of
      // baked-in hex, so code blocks recolor with the CorvidLabs --code-*
      // tokens and follow light/dark automatically. Mapping lives in globals.css.
      theme: 'css-variables',
    },
  },
})
