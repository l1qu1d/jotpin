#!/usr/bin/env node

import {mkdirSync, readFileSync, unlinkSync, writeFileSync} from "node:fs"
import {createRequire} from "node:module"
import {dirname, resolve} from "node:path"
import {fileURLToPath} from "node:url"

const scriptDirectory = dirname(fileURLToPath(import.meta.url))
const root = resolve(scriptDirectory, "..")
const buildDirectory = resolve(scriptDirectory, "vendor")
const require = createRequire(resolve(buildDirectory, "package.json"))
const {buildSync} = require("esbuild")
const outputDirectory = resolve(root, "markdown")
const temporaryBundle = resolve(outputDirectory, ".MarkdownParser.js.tmp")
const workerPath = resolve(outputDirectory, "MarkdownParserWorker.js")

mkdirSync(outputDirectory, {recursive: true})
buildSync({
  entryPoints: [resolve(buildDirectory, "markdown-entry.mjs")],
  outfile: temporaryBundle,
  bundle: true,
  format: "iife",
  globalName: "JotPinMarkdownParser",
  platform: "browser",
  // Prefer packages' worker exports. In particular, this keeps the named
  // character decoder from selecting its DOM implementation (`document` is
  // unavailable in QML WorkerScript).
  conditions: ["worker"],
  // Qt 6's QML JavaScript engine supports ES2015. Asking esbuild for ES5 is
  // both unnecessary and unsupported for parts of the unified/micromark
  // dependency graph.
  target: "es2015",
  minify: true,
  legalComments: "none",
  charset: "utf8"
})

function unicodePunctuationAndSymbolClass() {
  const matches = /[\p{P}\p{S}]/u
  const ranges = []
  let rangeStart = null
  let previous = null
  for (let code = 0; code <= 0xffff; code++) {
    if (matches.test(String.fromCharCode(code))) {
      if (rangeStart === null) rangeStart = code
      previous = code
    } else if (rangeStart !== null) {
      ranges.push([rangeStart, previous])
      rangeStart = null
    }
  }
  if (rangeStart !== null) ranges.push([rangeStart, previous])
  const escapeCode = code => `\\u${code.toString(16).padStart(4, "0")}`
  return "[" + ranges.map(range => range[0] === range[1]
    ? escapeCode(range[0])
    : escapeCode(range[0]) + "-" + escapeCode(range[1])).join("") + "]"
}

let bundle = readFileSync(temporaryBundle, "utf8")
unlinkSync(temporaryBundle)
// QJSEngine accepts Unicode regexes but not Unicode property escapes. The
// upstream micromark predicate converts one UTF-16 code unit with
// String.fromCharCode, so an exact generated BMP class preserves its behavior.
bundle = bundle.replaceAll("\\\\p{P}|\\\\p{S}",
  unicodePunctuationAndSymbolClass())
const worker = `var JOTPIN_MARKDOWN_PARSER_BUNDLE = ${JSON.stringify(bundle)}
var jotpinMarkdownParserEngine = null

function jotpinEnsureMarkdownParser() {
  if (!jotpinMarkdownParserEngine)
    jotpinMarkdownParserEngine = Function("var globalThis=this;var self=this;\\n" +
      JOTPIN_MARKDOWN_PARSER_BUNDLE +
      "\\n; return JotPinMarkdownParser;")()
  return jotpinMarkdownParserEngine
}

WorkerScript.onMessage = function(message) {
  if (String(message.type || "") !== "parse") return
  var key = String(message.key || "")
  var source = String(message.source || "")
  var startedAt = Date.now()
  try {
    var rendered = jotpinEnsureMarkdownParser().render(source)
    WorkerScript.sendMessage({
      type: "parsed",
      key: key,
      tree: rendered.tree,
      html: rendered.html,
      codeBlocks: rendered.codeBlocks,
      images: rendered.images,
      elapsedMs: Date.now() - startedAt
    })
  } catch (error) {
    WorkerScript.sendMessage({
      type: "parseError",
      key: key,
      message: String(error && error.name ? error.name + ": " : "") +
        String(error && error.message ? error.message : error) +
        String(error && error.stack ? "\\n" + error.stack : "")
    })
  }
}
`
writeFileSync(workerPath, worker)
console.log(`${workerPath} ${Buffer.byteLength(worker)} bytes`)
