#!/usr/bin/env node

import {execFileSync} from 'node:child_process'
import {copyFileSync, mkdirSync, readFileSync, unlinkSync, writeFileSync} from 'node:fs'
import {dirname, resolve} from 'node:path'
import {fileURLToPath} from 'node:url'

const scriptDirectory = dirname(fileURLToPath(import.meta.url))
const root = resolve(scriptDirectory, '..')
const buildRoot = resolve(scriptDirectory, 'vendor')
const browserify = resolve(buildRoot, 'node_modules/.bin/browserify')
const outputDirectory = resolve(root, 'vendor')
const spellDirectory = resolve(root, 'spellcheck')
const syntaxDirectory = resolve(root, 'syntax')
const licenseDirectory = resolve(outputDirectory, 'licenses')

function qmlStandalone(bundleValue, name) {
  const bundle = String(bundleValue || '')
  const compactAssignment = '("undefined"!=typeof window?window:"undefined"!=typeof global?global:"undefined"!=typeof self?self:this).' +
    name + '=e()'
  const readableAssignment = `g.${name} = f()`
  let adapted = bundle
  if (adapted.includes(compactAssignment))
    adapted = adapted.replace(compactAssignment, `${name}=e()`)
  else if (adapted.includes(readableAssignment))
    adapted = adapted.replace(readableAssignment, `${name} = f()`)
  else
    throw new Error(`Could not adapt the ${name} standalone bundle for QML`)
  adapted = adapted.replace(
    'function r(e,n,t){function o(i,f){',
    'function r(e,n,t){var u,i;function o(i,f){').replace(
    'for(var u="function"==typeof require&&require,i=0;',
    'for(u="function"==typeof require&&require,i=0;')
  return `var ${name}\n` + adapted
}

function qmlHighlightCompatibility(bundleValue) {
  return String(bundleValue || '').replace(
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
    // Qt's JavaScript engine rejects the Unicode identifier properties used
    // by Highlight.js' Python grammar. Keep its tokenizer functional with the
    // same ASCII identifier coverage used by the rest of JotPin's editor.
    .replace('const IDENT_RE = /[\\p{XID_Start}_]\\p{XID_Continue}*/u;',
      'const IDENT_RE = /[A-Za-z_][A-Za-z0-9_]*/;')
}

mkdirSync(outputDirectory, {recursive: true})
mkdirSync(spellDirectory, {recursive: true})
mkdirSync(syntaxDirectory, {recursive: true})
mkdirSync(licenseDirectory, {recursive: true})

execFileSync(browserify, [
  resolve(buildRoot, 'highlight-entry.cjs'),
  '--standalone', 'JotPinHighlight',
  '--outfile', resolve(outputDirectory, 'HighlightJs.js')
], {cwd: buildRoot, stdio: 'inherit'})
const highlightBundle = qmlHighlightCompatibility(qmlStandalone(
  readFileSync(resolve(outputDirectory, 'HighlightJs.js'), 'utf8'),
  'JotPinHighlight')).replace(
    "if ((type === 'object' || type === 'function') && !Object.isFrozen(prop)) {",
    "if (prop !== null && (type === 'object' || type === 'function') && !Object.isFrozen(prop)) {").replace(
    'if (typeof MODES[key] === "object") {',
    'if (MODES[key] !== null && typeof MODES[key] === "object") {')
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
unlinkSync(resolve(outputDirectory, 'HighlightJs.js'))

const temporaryNspell = resolve(outputDirectory, '.NSpell.js.tmp')
execFileSync(browserify, [
  resolve(buildRoot, 'nspell-entry.cjs'),
  '--standalone', 'JotPinNSpell',
  '--outfile', temporaryNspell
], {cwd: buildRoot, stdio: 'inherit'})

const aff = readFileSync(resolve(buildRoot,
  'node_modules/dictionary-en/index.aff'), 'utf8')
const dic = readFileSync(resolve(buildRoot,
  'node_modules/dictionary-en/index.dic'), 'utf8')
const nspellBundle = qmlStandalone(
  readFileSync(temporaryNspell, 'utf8'), 'JotPinNSpell')
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
unlinkSync(temporaryNspell)
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
copyFileSync(resolve(buildRoot, 'node_modules/nspell/node_modules/is-buffer/LICENSE'),
  resolve(licenseDirectory, 'is-buffer-MIT.txt'))
copyFileSync(resolve(buildRoot, 'node_modules/dictionary-en/license'),
  resolve(licenseDirectory, 'dictionary-en-MIT-BSD.txt'))
copyFileSync(resolve(buildRoot, 'node_modules/highlight.js/LICENSE'),
  resolve(licenseDirectory, 'highlight.js-BSD-3-Clause.txt'))
copyFileSync(resolve(buildRoot,
  'node_modules/@exercism/highlightjs-gdscript/LICENSE'),
  resolve(licenseDirectory, 'highlightjs-gdscript-MIT.txt'))
