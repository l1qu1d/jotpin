#!/usr/bin/env node

const assert = require("node:assert/strict")
const {mkdtemp, lstat, mkdir, open, readFile, readdir, rm, writeFile} = require("node:fs/promises")
const {tmpdir} = require("node:os")
const {basename, join, relative, resolve} = require("node:path")

// Mirrored from omacom/omarchy-plugin-marketplace main's
// scripts/security-baseline-scope.mjs (blob 7f31cb1f533bc1d884ee57d93fcece5d1b91cc0b).
// Keep this check offline: the submitted repository is scanned against this
// scope before the marketplace fetches its own snapshot.
const FILE_BYTE_LIMIT = 512 * 1024
const SNAPSHOT_BYTE_LIMIT = 8 * 1024 * 1024
const SNAPSHOT_FILE_LIMIT = 1000
const EXECUTABLE_PROBE_BYTES = 4096
const EXCLUDED_DIRECTORIES = new Set([
  ".github", "coverage", "docs", "fixtures", "node_modules", "spec", "specs", "test", "tests"
])
const SCANNED_EXTENSIONS = new Set([
  ".bash", ".cjs", ".desktop", ".fish", ".js", ".lua", ".mjs", ".pl", ".py", ".qml",
  ".rb", ".service", ".sh", ".sudoers", ".toml", ".yaml", ".yml", ".zsh"
])
const BINARY_ASSET_EXTENSIONS = new Set([
  ".apng", ".avif", ".bmp", ".gif", ".heic", ".heif", ".ico", ".jfif", ".jpe", ".jpeg",
  ".jpg", ".jxl", ".png", ".tif", ".tiff", ".webp"
])
const SETUP_LIKE_BASENAME = /(?:install|installer|setup|uninstall)/i
const ROOT_DIR = resolve(__dirname, "..")

function normalized(value) {
  return String(value || "").replaceAll("\\", "/")
}

function isRootReadme(path) {
  return !path.includes("/") && /^readme(?:\.[^/]+)?$/i.test(path)
}

function isBinaryAssetPath(path) {
  const fileName = basename(normalized(path)).toLowerCase()
  const extensionAt = fileName.lastIndexOf(".")
  return extensionAt > 0 && BINARY_ASSET_EXTENSIONS.has(fileName.slice(extensionAt))
}

function isSetupNamedPath(path) {
  return SETUP_LIKE_BASENAME.test(basename(normalized(path)))
}

function isSecurityScanPath(path) {
  const pathValue = normalized(path)
  if (!pathValue || pathValue.startsWith("/") || pathValue.includes("\0")) return false
  if (isRootReadme(pathValue)) return true
  const parts = pathValue.toLowerCase().split("/")
  if (parts.slice(0, -1).some((part) => EXCLUDED_DIRECTORIES.has(part))) return false
  const fileName = parts.at(-1)
  const extensionAt = fileName.lastIndexOf(".")
  const extension = extensionAt > 0 ? fileName.slice(extensionAt) : ""
  if (SCANNED_EXTENSIONS.has(extension)) return true
  if (isBinaryAssetPath(pathValue)) return false
  if (parts[0] === "bin" || parts[0] === "scripts") return extensionAt < 0
  return isSetupNamedPath(pathValue)
}

function isExcludedPath(path) {
  const parts = normalized(path).toLowerCase().split("/")
  return parts.slice(0, -1).some((part) => EXCLUDED_DIRECTORIES.has(part))
}

async function collectTree(root, directory = root, result = []) {
  for (const entry of await readdir(directory, {withFileTypes: true})) {
    if (entry.isDirectory() && [".git", ".agents", ".codex", "node_modules"].includes(entry.name)) continue
    const absolutePath = join(directory, entry.name)
    const path = normalized(relative(root, absolutePath))
    const info = await lstat(absolutePath)
    if (info.isDirectory()) {
      await collectTree(root, absolutePath, result)
    } else if (info.isFile() || info.isSymbolicLink()) {
      result.push({
        absolutePath,
        mode: info.isSymbolicLink() ? "120000" : ((info.mode & 0o111) ? "100755" : "100644"),
        path,
        size: info.size
      })
    }
  }
  return result
}

async function manifestEntryPoints(tree) {
  const manifest = tree.find((entry) => entry.path === "manifest.json" && entry.mode !== "120000")
  if (!manifest) return new Set()
  const parsed = JSON.parse(await readFile(manifest.absolutePath, "utf8"))
  return new Set(Object.values(parsed.entryPoints || {}).filter((path) => (
    typeof path === "string" && path && !path.startsWith("/") && !path.includes("..")
  )))
}

async function scanEntries(tree) {
  const forced = await manifestEntryPoints(tree)
  return tree.filter((entry) => {
    if (entry.mode === "120000") return false
    const forcedEntryPoint = forced.has(entry.path)
    if (isExcludedPath(entry.path) && !forcedEntryPoint) return false
    const extensionless = !basename(entry.path).includes(".")
    // The marketplace has a separate bounded probe for setup-named assets.
    // JotPin ships none. Fail closed here rather than claim a size-only pass
    // proves that special probe succeeds (even a tiny installer.png can fail).
    const setupNamedBinary = isBinaryAssetPath(entry.path) && isSetupNamedPath(entry.path)
    if (setupNamedBinary && entry.mode !== "100755" && !forcedEntryPoint)
      throw new Error(`${entry.path} requires upstream setup-asset probing; unsupported by this local gate`)
    return isSecurityScanPath(entry.path)
      || entry.mode === "100755"
      || extensionless
      || forcedEntryPoint
      || setupNamedBinary
  })
}

function executableProbeLooksBinary(entry, probe) {
  if (entry.size <= FILE_BYTE_LIMIT || entry.mode !== "100755") return true
  if (probe.length < 4) return false
  const magic = probe.subarray(0, 4)
  return magic.equals(Buffer.from([0x7f, 0x45, 0x4c, 0x46]))
    || magic.subarray(0, 2).equals(Buffer.from([0x4d, 0x5a]))
    || [0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe, 0xcafebabe]
      .includes(probe.readUInt32BE(0))
}

async function validateLimits(entries) {
  if (entries.length > SNAPSHOT_FILE_LIMIT) {
    throw new Error(`marketplace scan includes ${entries.length} files; limit is ${SNAPSHOT_FILE_LIMIT}`)
  }
  let totalBytes = 0
  for (const entry of entries) {
    if (entry.size > FILE_BYTE_LIMIT && entry.mode !== "100755") {
      throw new Error(`${entry.path} exceeds ${FILE_BYTE_LIMIT} bytes (${entry.size})`)
    }
    totalBytes += entry.size > FILE_BYTE_LIMIT ? EXECUTABLE_PROBE_BYTES : entry.size
  }
  if (totalBytes > SNAPSHOT_BYTE_LIMIT) {
    throw new Error(`marketplace scan includes ${totalBytes} bytes; limit is ${SNAPSHOT_BYTE_LIMIT}`)
  }
  for (const entry of entries) {
    if (entry.size <= FILE_BYTE_LIMIT || entry.mode !== "100755") continue
    const handle = await open(entry.absolutePath, "r")
    let probe
    try {
      const buffer = Buffer.alloc(EXECUTABLE_PROBE_BYTES)
      const {bytesRead} = await handle.read(buffer, 0, buffer.length, 0)
      probe = buffer.subarray(0, bytesRead)
    } finally {
      await handle.close()
    }
    if (!executableProbeLooksBinary(entry, probe)) {
      throw new Error(`${entry.path} exceeds ${FILE_BYTE_LIMIT} bytes and is not a supported executable binary`)
    }
  }
  return {fileCount: entries.length, totalBytes}
}

function assertScopeContract() {
  assert.equal(isSecurityScanPath("README.md"), true)
  assert.equal(isSecurityScanPath("spellcheck/DictionaryPart1.mjs"), true)
  assert.equal(isSecurityScanPath("tests/fixture.js"), false)
  assert.equal(isSecurityScanPath("docs/example.js"), false)
  assert.equal(isSecurityScanPath("package-lock.json"), false)
  assert.equal(isSecurityScanPath("bin/launcher"), true)
  assert.equal(isSecurityScanPath("scripts/launcher"), true)
  assert.equal(isSecurityScanPath("assets/preview.png"), false)
  assert.equal(isSecurityScanPath("share/installer.json"), true)
}

async function assertOversizedFixtureDetected() {
  const fixtureRoot = await mkdtemp(join(tmpdir(), "jotpin-marketplace-packaging."))
  try {
    const oversizedPath = join(fixtureRoot, "generated-worker.js")
    await writeFile(oversizedPath, Buffer.alloc(FILE_BYTE_LIMIT + 1, 0x78))
    const entries = await scanEntries(await collectTree(fixtureRoot))
    assert.ok(entries.some((entry) => entry.path === "generated-worker.js"))
    await assert.rejects(validateLimits(entries), /generated-worker\.js exceeds 524288 bytes/)

    await mkdir(join(fixtureRoot, "tests"))
    await writeFile(join(fixtureRoot, "tests", "ignored-worker.js"), Buffer.alloc(FILE_BYTE_LIMIT + 1, 0x78))
    const excluded = await scanEntries(await collectTree(fixtureRoot))
    assert.equal(excluded.some((entry) => entry.path === "tests/ignored-worker.js"), false)

    await writeFile(join(fixtureRoot, "installer.png"),
      Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))
    await assert.rejects(scanEntries(await collectTree(fixtureRoot)), /requires upstream setup-asset probing/)
    await rm(join(fixtureRoot, "installer.png"))

    // A sparse executable proves the probe does not allocate/read the full file.
    const executablePath = join(fixtureRoot, "tool")
    const executable = await open(executablePath, "w")
    try {
      await executable.write(Buffer.from([0x7f, 0x45, 0x4c, 0x46]))
      await executable.truncate(1024 * 1024 * 1024)
    } finally {
      await executable.close()
    }
    assert.deepEqual(await validateLimits([{path: "tool", absolutePath: executablePath,
      mode: "100755", size: 1024 * 1024 * 1024}]),
      {fileCount: 1, totalBytes: EXECUTABLE_PROBE_BYTES})

    await assert.rejects(() => validateLimits(Array.from({length: SNAPSHOT_FILE_LIMIT + 1}, (_, index) => ({
      mode: "100644", path: `file-${index}.js`, size: 0
    }))), /limit is 1000/)
    await assert.rejects(() => validateLimits(Array.from({length: 17}, (_, index) => ({
      mode: "100644", path: `file-${index}.js`, size: FILE_BYTE_LIMIT
    }))), /limit is 8388608/)
  } finally {
    await rm(fixtureRoot, {force: true, recursive: true})
  }
}

async function main() {
  assertScopeContract()
  await assertOversizedFixtureDetected()
  const entries = await scanEntries(await collectTree(ROOT_DIR))
  const limits = await validateLimits(entries)
  const largest = [...entries].sort((left, right) => right.size - left.size)[0]
  console.log(`MARKETPLACE_PACKAGING_SCAN: ${JSON.stringify({
    files: limits.fileCount,
    bytes: limits.totalBytes,
    largest: largest ? {path: largest.path, bytes: largest.size} : null
  })}`)
  console.log("PASS: marketplace scanner scope and package limits are enforced")
}

main().catch((error) => {
  console.error(`FAIL: ${error.message}`)
  process.exitCode = 1
})
