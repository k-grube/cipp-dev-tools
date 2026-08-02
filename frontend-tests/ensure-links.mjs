// junction the context-bearing libs into node_modules so every resolution path
// (vite transform or externalized cjs require) lands on the clone's single copy
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const dirname = path.dirname(fileURLToPath(import.meta.url))
const cippFrontend = path.resolve(dirname, '../CIPP/frontend')
const cippModules = path.join(cippFrontend, 'node_modules')
const localModules = path.join(dirname, 'node_modules')

function isLink(p) {
  try {
    return fs.lstatSync(p).isSymbolicLink()
  } catch {
    return false
  }
}

// tests import ../../src/*, the whole tree is a junction into the CIPP clone
const srcLink = path.join(dirname, 'src')
const srcTarget = path.join(cippFrontend, 'src')
if (!fs.existsSync(srcTarget)) {
  console.error('missing CIPP/frontend/src (clone CIPP first: run setup.ps1 / setup.sh)')
  process.exit(1)
}
if (!isLink(srcLink)) {
  if (fs.existsSync(srcLink)) {
    console.error('frontend-tests/src exists but is not a junction, refusing to replace it')
    process.exit(1)
  }
  fs.symlinkSync(srcTarget, srcLink, 'junction')
}

const singletons = [
  'react',
  'react-dom',
  '@mui/material',
  '@mui/system',
  '@mui/icons-material',
  '@emotion/react',
  '@emotion/styled',
  '@tanstack/react-query',
  'react-redux',
  '@reduxjs/toolkit',
  'react-hook-form',
  '@heroicons/react',
  '@tiptap/core',
  'javascript-time-ago',
  // preview.jsx resolves from the mirror's node_modules (source files realpath into the CIPP tree)
  '@mui/x-date-pickers',
  // not a singleton, vi.mock ids must resolve identically from tests and source
  '@monaco-editor/react',
  // @storybook/react's preset.js statically imports typescript despite being an optional peer dep, throws without it and kills renderToCanvas for every story
  'typescript',
  // optimizeDeps.include resolves from this root, junction so the browser-project pre-bundle works instead of a mid-run re-optimize
  'material-react-table',
]

for (const pkg of singletons) {
  const target = path.join(cippModules, pkg)
  const link = path.join(localModules, pkg)
  if (!fs.existsSync(target)) {
    console.error(`missing in CIPP/frontend/node_modules: ${pkg} (run yarn install in CIPP/frontend)`)
    process.exit(1)
  }
  if (isLink(link)) {
    continue
  }
  if (fs.existsSync(link)) {
    // npm ci/install materializes real copies (hard deps like @storybook/addon-docs -> react), junction must win or react dualizes
    fs.rmSync(link, { recursive: true, force: true })
  }
  fs.mkdirSync(path.dirname(link), { recursive: true })
  fs.symlinkSync(target, link, 'junction')
}

// storybook staticDirs
const publicLink = path.join(dirname, 'public')
const publicTarget = path.join(cippFrontend, 'public')
if (!isLink(publicLink) && fs.existsSync(publicTarget)) {
  fs.symlinkSync(publicTarget, publicLink, 'junction')
}
