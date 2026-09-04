const assert = require('node:assert/strict')
const Spellcheck = require('../SpellcheckModel.js')

function words(source) {
  return Spellcheck.spellingCandidates(source).map((candidate) => candidate.word)
}

{
  const source = [
    '# Heding prose',
    '',
    'A mispelled word and `codewurd`.',
    '[Visible label](https://example.test/badwurd)',
    '',
    '```js',
    'const codewurd = true',
    '```'
  ].join('\n')
  const result = words(source)
  assert(result.includes('Heding'))
  assert(result.includes('mispelled'))
  assert(result.includes('Visible'))
  assert(result.includes('label'))
  assert(!result.includes('codewurd'))
  assert(!result.includes('https'))
  assert(!result.includes('example'))
  assert(!result.includes('badwurd'))
}

{
  const before = 'Mispelled prose.\n```python\nprint(message)\n```\nAfter text.'
  const after = 'Mispelled prose.\n```python\nprint(message + value)\n```\nAfter text.'
  const previousCandidates = Spellcheck.spellingCandidates(before)
  const nextCandidates = Spellcheck.spellingCandidates(after)
  const misspelledIndex = previousCandidates.findIndex(
    (candidate) => candidate.word === 'Mispelled')
  const previousRange = {
    word: 'Mispelled', checkWord: 'Mispelled',
    start: previousCandidates[misspelledIndex].start,
    end: previousCandidates[misspelledIndex].end,
    candidateIndex: misspelledIndex
  }
  const rebased = Spellcheck.rebaseMisspellings(
    previousCandidates, nextCandidates, [previousRange])
  assert(rebased)
  assert.equal(rebased.length, 1)
  assert.equal(rebased[0].start, nextCandidates[misspelledIndex].start)
  assert.equal(rebased[0].end, nextCandidates[misspelledIndex].end)
  assert.equal(Spellcheck.candidateSequencesEqual(
    previousCandidates, nextCandidates), true)

  const proseEditCandidates = Spellcheck.spellingCandidates(
    after.replace('After', 'Different'))
  assert.equal(Spellcheck.rebaseMisspellings(
    previousCandidates, proseEditCandidates, [previousRange]), null)
}

{
  const source = [
    'Outside mispelled prose.',
    '',
    '```javascript',
    'const fencedwurd = "mispelled"',
    '```',
    '',
    '~~~text',
    'tildefencedwurd',
    '~~~',
    '',
    '```python',
    'unclosedfencedwurd'
  ].join('\n')
  const candidates = Spellcheck.spellingCandidates(source)
  const result = candidates.map((candidate) => candidate.word)
  assert(result.includes('mispelled'))
  for (const codeWord of [
    'javascript', 'const', 'fencedwurd', 'tildefencedwurd',
    'python', 'unclosedfencedwurd'
  ]) {
    assert(!result.includes(codeWord), `${codeWord} must stay outside spellcheck`)
  }

  const leakedWorkerRanges = [
    {word: 'mispelled', start: source.indexOf('mispelled'),
      end: source.indexOf('mispelled') + 'mispelled'.length},
    {word: 'fencedwurd', start: source.indexOf('fencedwurd'),
      end: source.indexOf('fencedwurd') + 'fencedwurd'.length}
  ]
  assert.deepEqual(
    Spellcheck.withoutExcludedMarkdownRanges(source, leakedWorkerRanges),
    [leakedWorkerRanges[0]],
    'the UI-boundary filter must reject a worker range inside fenced code')

  const proseCandidateIndex = candidates.findIndex(
    (candidate) => candidate.word === 'mispelled')
  const validWorkerRange = {
    word: candidates[proseCandidateIndex].sourceWord,
    checkWord: candidates[proseCandidateIndex].word,
    start: candidates[proseCandidateIndex].start,
    end: candidates[proseCandidateIndex].end,
    candidateIndex: proseCandidateIndex
  }
  assert.deepEqual(
    Spellcheck.validatedMisspellings(candidates, [validWorkerRange,
      {...validWorkerRange, start: validWorkerRange.start + 1}]),
    [validWorkerRange],
    'only ranges matching the worker candidate contract may reach geometry')
}

{
  const source = '- [ ] Taskwurd\n> Quotewurd\n\n| Colwurd | Value |\n| --- | --- |\n| Rowwurd | text |'
  const result = words(source)
  for (const word of ['Taskwurd', 'Quotewurd', 'Colwurd', 'Rowwurd'])
    assert(result.includes(word), `${word} should remain spellcheckable prose`)
}

{
  const source = "First\r\nThat’s mispelled"
  const candidates = Spellcheck.spellingCandidates(source)
  const curly = candidates.find((candidate) => candidate.sourceWord === 'That’s')
  const misspelled = candidates.find((candidate) => candidate.word === 'mispelled')
  assert.equal(curly.word, "That's")
  assert.equal(source.slice(curly.start, curly.end), 'That’s')
  assert.equal(source.slice(misspelled.start, misspelled.end), 'mispelled')
  assert.equal(Spellcheck.rangeAtPosition(candidates, misspelled.start + 2), misspelled)
}

{
  const source = '[ref]: https://example.test/wurd\n    indented_code_wurd\nNormal prose'
  const result = words(source)
  assert(!result.includes('ref'))
  assert(!result.includes('indented'))
  assert(result.includes('Normal'))
  assert(result.includes('prose'))
}

{
  const source = [
    'https http www https://badwurd.example/pathwurd',
    'Visit badwurd.example/docs or email badwurd@example.test.',
    'Open /home/mode/badwurd.md or C:\\Users\\badwurd\\note.md.',
    'Entity &#x20; and &nbsp; plus JotPin camelCaseValue.',
    'Actual mispelled prose remains.'
  ].join('\n')
  const result = words(source)
  for (const technical of [
    'https', 'http', 'www', 'badwurd', 'example', 'pathwurd', 'docs',
    'home', 'mode', 'Users', 'note', 'x', 'nbsp', 'JotPin', 'camelCaseValue'
  ]) {
    assert(!result.includes(technical), `${technical} should be treated as technical text`)
  }
  assert(result.includes('mispelled'))
  assert(result.includes('prose'))
}

{
  const before = 'Alpha mispelled.\nBeta steady.'
  const next = 'Alpha misspelled.\nBeta steady.'
  const edit = Spellcheck.deriveSpellcheckEdit(before, next)
  assert.deepEqual(edit, {
    start: 9,
    deletedLength: 0,
    insertedText: 's',
    oldEnd: 9,
    newEnd: 10,
    delta: 1
  })
  assert.equal(before.slice(0, edit.start) + edit.insertedText +
    before.slice(edit.oldEnd), next)
}

{
  const before = 'Alpha added prose.'
  const next = 'Alpha prose.'
  const edit = Spellcheck.deriveSpellcheckEdit(before, next)
  assert.deepEqual(edit, {
    start: 6,
    deletedLength: 6,
    insertedText: '',
    oldEnd: 12,
    newEnd: 6,
    delta: -6
  })
}

{
  const before = 'First\r\nSecond wurd\r\nThird'
  const next = 'First\r\nSecond word\r\nThird'
  const edit = Spellcheck.deriveSpellcheckEdit(before, next)
  assert.equal(edit.start, before.indexOf('wurd') + 1)
  assert.equal(edit.deletedLength, 1)
  assert.equal(edit.insertedText, 'o')
  assert.equal(before.slice(0, edit.start) + edit.insertedText +
    before.slice(edit.oldEnd), next)
}

{
  const before = 'A \ud83d\ude42 typo'
  const next = 'A \ud83d\ude42 fixed typo'
  const edit = Spellcheck.deriveSpellcheckEdit(before, next)
  assert.equal(edit.start, 5)
  assert.equal(edit.insertedText, 'fixed ')
}

console.log('PASS: Markdown-aware spellcheck candidate extraction')
