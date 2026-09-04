#!/usr/bin/env node

const assert = require("node:assert/strict")
const model = require("../EditorModel.js")

function mixedNote(targetLength) {
  const sections = []
  let length = 0
  let index = 0
  while (length < targetLength) {
    const section =
      `## Section ${index}\n\n` +
      `Paragraph ${index} has **bold Markdown**, an [internal link](note-${index}.md), ` +
      "and enough ordinary text to exercise searching and edit transactions.\n\n" +
      `- item ${index}\n- [ ] task ${index}\n\n` +
      "```javascript\nconst value = " + index + "\n```"
    sections.push(section)
    length += section.length + (sections.length > 1 ? 2 : 0)
    index++
  }
  return sections.join("\n\n").slice(0, targetLength)
}

function elapsedMilliseconds(callback) {
  const started = process.hrtime.bigint()
  callback()
  return Number(process.hrtime.bigint() - started) / 1e6
}

function benchmarkEdits(name, length, repetitions, budgetMs) {
  const source = mixedNote(length)
  const positions = [0, Math.floor(source.length / 2), source.length]
  let transactionCount = 0
  const elapsedMs = elapsedMilliseconds(() => {
    for (let repetition = 0; repetition < repetitions; repetition++) {
      for (const position of positions) {
        const after = source.slice(0, position) + "x" + source.slice(position)
        const transaction = model.makeEditTransaction(
          source, after,
          { cursor: position, selectionStart: position, selectionEnd: position },
          { cursor: position + 1, selectionStart: position + 1,
            selectionEnd: position + 1 },
          repetition
        )
        assert.ok(transaction, `${name} edit transaction exists`)
        assert.equal(transaction.start, position,
          `${name} edit transaction keeps the exact insertion offset`)
        assert.equal(transaction.removed, "",
          `${name} edit transaction removes no source`)
        assert.equal(transaction.inserted, "x",
          `${name} edit transaction inserts the requested source`)
        transactionCount++
      }
    }
  })
  assert.ok(elapsedMs < budgetMs,
    `${name} edit transactions took ${elapsedMs.toFixed(1)} ms; budget ${budgetMs} ms`)
  return { bytes: source.length, operations: transactionCount,
    elapsedMs: Number(elapsedMs.toFixed(1)), budgetMs }
}

function benchmarkFind(name, length, repetitions, budgetMs) {
  const marker = "UNIQUE-JOTPIN-PERFORMANCE-MARKER"
  const source = mixedNote(Math.max(0, length - marker.length - 2)) +
    "\n\n" + marker
  let result = null
  const elapsedMs = elapsedMilliseconds(() => {
    for (let repetition = 0; repetition < repetitions; repetition++) {
      result = model.findText(source, marker, 0, false, true)
      assert.equal(result.found, true, `${name} find locates its marker`)
      assert.equal(result.start, source.length - marker.length,
        `${name} find returns the marker's exact source offset`)
      assert.equal(result.count, 1,
        `${name} find reports the exact match count`)
    }
  })
  assert.ok(elapsedMs < budgetMs,
    `${name} find operations took ${elapsedMs.toFixed(1)} ms; budget ${budgetMs} ms`)
  return { bytes: source.length, operations: repetitions,
    elapsedMs: Number(elapsedMs.toFixed(1)), budgetMs }
}

const results = {
  editTransactions: [
    benchmarkEdits("small-note", 1024, 100, 100),
    benchmarkEdits("normal-note", 10 * 1024, 50, 150),
    benchmarkEdits("long-note", 100 * 1024, 10, 250),
    benchmarkEdits("large-note", 1024 * 1024, 2, 500)
  ],
  find: [
    benchmarkFind("small-note", 1024, 100, 100),
    benchmarkFind("normal-note", 10 * 1024, 50, 200),
    benchmarkFind("long-note", 100 * 1024, 10, 500),
    benchmarkFind("large-note", 1024 * 1024, 2, 750)
  ]
}

process.stdout.write(`PERF_MODEL_RESULT: ${JSON.stringify(results)}\n`)
process.stdout.write("PASS: editor-model performance baseline stayed within its regression budgets\n")
