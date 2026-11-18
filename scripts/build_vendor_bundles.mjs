#!/usr/bin/env node

import {createRequire} from 'node:module'
import {copyFileSync, mkdirSync, readFileSync, writeFileSync} from 'node:fs'
import {dirname, resolve} from 'node:path'
import {fileURLToPath} from 'node:url'

const scriptDirectory = dirname(fileURLToPath(import.meta.url))
const root = resolve(scriptDirectory, '..')
const buildRoot = resolve(scriptDirectory, 'vendor')
const require = createRequire(resolve(buildRoot, 'package.json'))
const {build} = require('esbuild')
const outputDirectory = resolve(root, 'vendor')
const spellDirectory = resolve(root, 'spellcheck')
const syntaxDirectory = resolve(root, 'syntax')
const licenseDirectory = resolve(outputDirectory, 'licenses')

function qmlHighlightCore(source) {
  return source.replace(
    'function _highlight(languageName, codeToHighlight, ignoreIllegals, continuation) {',
    'function _highlight(languageName, codeToHighlight, ignoreIllegals, continuation) {\n' +
    '    var language, md, result, top, continuations, emitter, modeBuffer, relevance, index, iterations, resumeScanAtSamePosition;'
  ).replace('    const language = getLanguage(languageName);',
    '    language = getLanguage(languageName);'
  ).replace('    const md = compileLanguage(language);',
    '    md = compileLanguage(language);'
  ).replace("    let result = '';", "    result = '';")
    .replace('    let top = continuation || md;', '    top = continuation || md;')
    .replace('    const continuations = {}; // keep continuations for sub-languages',
      '    continuations = {}; // keep continuations for sub-languages')
    .replace('    const emitter = new options.__emitter(options);',
      '    emitter = new options.__emitter(options);')
    .replace("    let modeBuffer = '';", "    modeBuffer = '';")
    .replace('    let relevance = 0;', '    relevance = 0;')
    .replace('    let index = 0;', '    index = 0;')
    .replace('    let iterations = 0;', '    iterations = 0;')
    .replace('    let resumeScanAtSamePosition = false;',
      '    resumeScanAtSamePosition = false;')
    .replace("if ((type === 'object' || type === 'function') && !Object.isFrozen(prop)) {",
      "if (prop !== null && (type === 'object' || type === 'function') && !Object.isFrozen(prop)) {")
    .replace('if (typeof MODES[key] === "object") {',
      'if (MODES[key] !== null && typeof MODES[key] === "object") {')
}

const highlightCompatibility = {
  name: 'qml-highlight-compatibility',
  setup(build) {
    build.onLoad({filter: /highlight\.js\/lib\/(core|languages\/python)\.js$/}, ({path}) => {
      const source = readFileSync(path, 'utf8')
      // QJSEngine does not support the Python grammar's Unicode identifier escapes.
      const contents = path.endsWith('/python.js')
        ? source.replace('const IDENT_RE = /[\\p{XID_Start}_]\\p{XID_Continue}*/u;',
          'const IDENT_RE = /[A-Za-z_][A-Za-z0-9_]*/;')
        : qmlHighlightCore(source)
      if (contents === source) throw new Error(`Could not adapt Highlight.js for QML: ${path}`)
      return {contents, loader: 'js'}
    })
  }
}

async function qmlBundle(entryPoint, globalName, plugins = []) {
  const result = await build({
    entryPoints: [resolve(buildRoot, entryPoint)],
    bundle: true,
    format: 'iife',
    globalName,
    platform: 'browser',
    target: 'es2015',
    minify: true,
    legalComments: 'none',
    charset: 'utf8',
    write: false,
    plugins
  })
  return result.outputFiles[0].text
}

mkdirSync(outputDirectory, {recursive: true})
mkdirSync(spellDirectory, {recursive: true})
mkdirSync(syntaxDirectory, {recursive: true})
mkdirSync(licenseDirectory, {recursive: true})

const [highlightBundle, nspellBundle] = await Promise.all([
  qmlBundle('highlight-entry.cjs', 'JotPinHighlight', [highlightCompatibility]),
  qmlBundle('nspell-entry.cjs', 'JotPinNSpell')
])
writeFileSync(resolve(syntaxDirectory, 'HighlightWorker.js'), `var JOTPIN_HIGHLIGHT_BUNDLE = ${JSON.stringify(highlightBundle)}
var jotpinHighlightEngine = null

function jotpinEnsureHighlightEngine() {
  if (!jotpinHighlightEngine)
    jotpinHighlightEngine = Function(JOTPIN_HIGHLIGHT_BUNDLE +
      '\\n; return JotPinHighlight;')()
  return jotpinHighlightEngine
}

WorkerScript.onMessage = function(message) {
  if (String(message.type || '') !== 'highlight') return
  var engine = jotpinEnsureHighlightEngine()
  WorkerScript.sendMessage({
    type: 'highlighted',
    key: String(message.key || ''),
    markup: engine.highlight(
      String(message.code || ''),
      String(message.language || ''),
      message.dark !== false)
  })
}
`)
const aff = readFileSync(resolve(buildRoot,
  'node_modules/dictionary-en/index.aff'), 'utf8')
const dic = readFileSync(resolve(buildRoot,
  'node_modules/dictionary-en/index.dic'), 'utf8')
const spellcheckRuntime = readFileSync(resolve(scriptDirectory,
  'SpellcheckWorkerRuntime.js'), 'utf8')

// Keep dictionary data readable and below the marketplace's 512 KiB file limit.
// Join the original lines exactly, including the final newline and Hunspell flags.
const dictionaryLines = dic.split('\n')
const dictionaryMiddle = Math.ceil(dictionaryLines.length / 2)
const dictionaryParts = [dictionaryLines.slice(0, dictionaryMiddle),
  dictionaryLines.slice(dictionaryMiddle)]
for (const [index, lines] of dictionaryParts.entries()) {
  const data = '// Generated from dictionary-en; see vendor/licenses/dictionary-en-MIT-BSD.txt.\n' +
    'export default [\n' + lines.map(line => JSON.stringify(line)).join(',\n') +
    '\n].join("\\n")' + (index === 0 ? ' + "\\n"' : '') + '\n'
  if (Buffer.byteLength(data) > 512 * 1024)
    throw new Error('Generated dictionary part exceeds the marketplace file limit')
  writeFileSync(resolve(spellDirectory, `DictionaryPart${index + 1}.mjs`), data)
}

const worker = `import dictionaryPart1 from './DictionaryPart1.mjs'
import dictionaryPart2 from './DictionaryPart2.mjs'
var JOTPIN_NSPELL_BUNDLE = ${JSON.stringify(nspellBundle)}
var JOTPIN_AFF = ${JSON.stringify(aff)}
var JOTPIN_DIC = dictionaryPart1 + dictionaryPart2
${spellcheckRuntime}`

writeFileSync(resolve(spellDirectory, 'SpellcheckWorker.mjs'), worker)
writeFileSync(resolve(outputDirectory, 'VERSIONS.json'), JSON.stringify({
  ...JSON.parse(readFileSync(resolve(outputDirectory, 'VERSIONS.json'), 'utf8')),
  generatedBy: 'scripts/build_vendor_bundles.mjs',
  highlightJs: '11.12.0',
  highlightJsGdscript: '0.0.1',
  nspell: '2.1.5',
  dictionaryEn: '4.0.0'
}, null, 2) + '\n')

copyFileSync(resolve(buildRoot, 'node_modules/nspell/license'),
  resolve(licenseDirectory, 'nspell-MIT.txt'))
const spellcheckRequire = createRequire(require.resolve('nspell'))
copyFileSync(resolve(dirname(spellcheckRequire.resolve('is-buffer/package.json')), 'LICENSE'),
  resolve(licenseDirectory, 'is-buffer-MIT.txt'))
copyFileSync(resolve(buildRoot, 'node_modules/dictionary-en/license'),
  resolve(licenseDirectory, 'dictionary-en-MIT-BSD.txt'))
copyFileSync(resolve(buildRoot, 'node_modules/highlight.js/LICENSE'),
  resolve(licenseDirectory, 'highlight.js-BSD-3-Clause.txt'))
copyFileSync(resolve(buildRoot,
  'node_modules/@exercism/highlightjs-gdscript/LICENSE'),
  resolve(licenseDirectory, 'highlightjs-gdscript-MIT.txt'))
