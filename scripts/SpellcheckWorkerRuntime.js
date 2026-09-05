function jotpinExcludedMarkdownRanges(source) {
  var ranges = []
  var lineStart = 0
  var inFence = false
  var fenceMarker = ''
  var fenceLength = 0
  while (lineStart <= source.length) {
    var newline = source.indexOf('\n', lineStart)
    var lineEnd = newline < 0 ? source.length : newline
    var line = source.slice(lineStart, lineEnd).replace(/\r$/, '')
    var fence = line.match(/^\s{0,3}(`{3,}|~{3,})/)
    if (fence) {
      var marker = fence[1][0]
      if (!inFence) {
        inFence = true
        fenceMarker = marker
        fenceLength = fence[1].length
      } else if (marker === fenceMarker && fence[1].length >= fenceLength) {
        inFence = false
      }
      ranges.push({start: lineStart, end: newline < 0 ? lineEnd : newline + 1})
    } else if (inFence || /^ {4}\S/.test(line) ||
        /^\[[^\]]+\]:\s*\S+/.test(line)) {
      ranges.push({start: lineStart, end: newline < 0 ? lineEnd : newline + 1})
    } else {
      var linkPattern = /!?(?:\[[^\]]*\])\((?:\\.|[^)\n])*\)/g
      var patterns = [
        /`+[^`\n]*`+/g,
        linkPattern,
        /&(?:#(?:x[0-9A-F]+|\d+)|[A-Za-z][A-Za-z0-9]+);/g,
        /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/gi,
        /\b(?:[A-Za-z][A-Za-z0-9+.-]*:\/\/|www\.)[^\s<>()]+/gi,
        /\b(?:localhost|[A-Za-z0-9](?:[A-Za-z0-9-]*\.)+[A-Za-z]{2,})(?::\d+)?(?:\/[^\s<>()]*)?/gi,
        /(?:^|[\s(])(?:~\/|\/)[^\s<>()]+/g,
        /\b[A-Za-z]:\\[^\s<>]+/g,
        /<\/?[A-Za-z][^>\n]*>/g
      ]
      for (var patternIndex = 0; patternIndex < patterns.length; patternIndex++) {
        var match
        while ((match = patterns[patternIndex].exec(line)) !== null) {
          if (patterns[patternIndex] === linkPattern) {
            var labelEnd = match[0].indexOf('](')
            if (labelEnd >= 0) {
              ranges.push({start: lineStart + match.index + labelEnd + 1,
                end: lineStart + match.index + match[0].length})
              continue
            }
          }
          ranges.push({start: lineStart + match.index,
            end: lineStart + match.index + match[0].length})
        }
      }
    }
    if (newline < 0) break
    lineStart = newline + 1
  }
  ranges.sort(function(a, b) { return a.start - b.start || a.end - b.end })
  return ranges
}

function jotpinSpellingCandidates(sourceValue) {
  var source = String(sourceValue || '')
  var exclusions = jotpinExcludedMarkdownRanges(source)
  var exclusionIndex = 0
  var candidates = []
  var pattern = /[A-Za-z](?:[A-Za-z]|['’](?=[A-Za-z]))*/g
  var technicalWords = {
    ftp: true, ftps: true, http: true, https: true, localhost: true,
    ssh: true, uri: true, url: true, urls: true, www: true
  }
  var match
  while ((match = pattern.exec(source)) !== null) {
    var start = match.index
    var end = start + match[0].length
    while (exclusionIndex < exclusions.length &&
        exclusions[exclusionIndex].end <= start) exclusionIndex++
    if (exclusionIndex < exclusions.length &&
        start >= exclusions[exclusionIndex].start &&
        start < exclusions[exclusionIndex].end) continue
    var before = start > 0 ? source[start - 1] : ''
    var after = end < source.length ? source[end] : ''
    if (/[0-9_]/.test(before) || /[0-9_]/.test(after)) continue
    var normalized = match[0].replace(/’/g, "'")
    if (technicalWords[normalized.toLowerCase()] ||
        /[a-z][A-Z]/.test(normalized)) continue
    candidates.push({word: normalized, sourceWord: match[0],
      start: start, end: end})
  }
  return candidates
}

var JotPinNSpell = null
var jotpinChecker = null
// Keep product names and common JotPin/Omarchy writing vocabulary available
// in every installation without treating them as user-added personal words.
var jotpinBundledWords = [
  'autosave', 'autosaves', 'callout', 'callouts',
  'CommonMark', 'commonmark', 'GDScript', 'gdscript',
  'GFM', 'gfm', 'GTK', 'gtk', 'Hyprland', 'hyprland',
  "Hyprland's", "hyprland's", 'IPC', 'ipc', 'JSON', 'json',
  'JotPin', 'jotpin', "JotPin's", "jotpin's", 'KDE', 'kde',
  'Lua', 'lua', 'mdast', 'micromark', 'npm', 'nspell',
  'Omarchy', 'omarchy', "Omarchy's", "omarchy's", 'PNG', 'png',
  'QML', 'qml', 'Quickshell', 'quickshell', "Quickshell's",
  "quickshell's", 'strikethrough', 'systemd', 'todo', 'todos',
  'Wayland', 'wayland', 'xdg', 'YAML', 'yaml'
]
var jotpinPersonalWords = []
var jotpinIgnoredWords = Object.create(null)
var jotpinCorrectCache = Object.create(null)
var jotpinCorrectCacheSize = 0
var jotpinCorrectCacheLimit = 4096
var jotpinCachedSource = ''
var jotpinCachedLines = []
var jotpinDocumentInitialized = false
var jotpinDictionaryRevision = 0

function jotpinNormalizedWord(value) {
  return String(value || '').replace(/’/g, "'").toLowerCase()
}

function jotpinEnsureChecker() {
  if (jotpinChecker) return jotpinChecker
  if (!JotPinNSpell)
    JotPinNSpell = Function(JOTPIN_NSPELL_BUNDLE +
      '\n; return JotPinNSpell;')()
  jotpinChecker = JotPinNSpell(JOTPIN_AFF, JOTPIN_DIC)
  for (var bundledIndex = 0;
       bundledIndex < jotpinBundledWords.length; bundledIndex++)
    jotpinChecker.add(jotpinBundledWords[bundledIndex])
  for (var index = 0; index < jotpinPersonalWords.length; index++)
    jotpinChecker.add(jotpinPersonalWords[index])
  return jotpinChecker
}

function jotpinSetPersonalWords(wordsValue) {
  var values = Array.isArray(wordsValue) ? wordsValue : []
  var unique = Object.create(null)
  jotpinPersonalWords = []
  for (var index = 0; index < values.length; index++) {
    var word = String(values[index] || '').trim()
    var normalized = jotpinNormalizedWord(word)
    if (!word || unique[normalized]) continue
    unique[normalized] = true
    jotpinPersonalWords.push(word)
  }
  jotpinChecker = null
  jotpinCorrectCache = Object.create(null)
  jotpinCorrectCacheSize = 0
  jotpinDictionaryRevision++
}

function jotpinWordMisspelled(wordValue) {
  var word = String(wordValue || '')
  var normalized = jotpinNormalizedWord(word)
  if (!word || jotpinIgnoredWords[normalized]) return false
  var correct = jotpinCorrectCache[normalized]
  if (correct === undefined) {
    correct = jotpinEnsureChecker().correct(word)
    if (jotpinCorrectCacheSize >= jotpinCorrectCacheLimit) {
      jotpinCorrectCache = Object.create(null)
      jotpinCorrectCacheSize = 0
    }
    jotpinCorrectCache[normalized] = correct
    jotpinCorrectCacheSize++
  }
  return !correct
}

function jotpinLineEnd(source, start) {
  var newline = source.indexOf('\n', start)
  return newline < 0 ? source.length : newline + 1
}

function jotpinFenceStateAfter(lineValue, beforeState) {
  var line = String(lineValue || '').replace(/\n$/, '').replace(/\r$/, '')
  var fence = line.match(/^\s{0,3}(`{3,}|~{3,})/)
  if (!fence) return String(beforeState || '')
  var marker = fence[1][0]
  var length = fence[1].length
  var current = String(beforeState || '')
  if (!current) return marker + ':' + length
  var separator = current.indexOf(':')
  var currentMarker = current.slice(0, separator)
  var currentLength = Number(current.slice(separator + 1)) || 3
  return marker === currentMarker && length >= currentLength ? '' : current
}

function jotpinBuildLineEntry(textValue, beforeState, metrics) {
  var text = String(textValue || '')
  var plainLine = text.replace(/\n$/, '').replace(/\r$/, '')
  var fence = /^\s{0,3}(`{3,}|~{3,})/.test(plainLine)
  var candidates = beforeState || fence ? [] : jotpinSpellingCandidates(text)
  var misspelled = new Array(candidates.length)
  for (var index = 0; index < candidates.length; index++) {
    misspelled[index] = jotpinWordMisspelled(candidates[index].word)
    metrics.checkedCandidateCount++
  }
  metrics.parsedLineCount++
  return {text: text, stateBefore: String(beforeState || ''),
    stateAfter: jotpinFenceStateAfter(text, beforeState),
    candidates: candidates, misspelled: misspelled,
    dictionaryRevision: jotpinDictionaryRevision, start: 0}
}

function jotpinUpdateLineStarts() {
  var start = 0
  for (var index = 0; index < jotpinCachedLines.length; index++) {
    jotpinCachedLines[index].start = start
    start += String(jotpinCachedLines[index].text || '').length
  }
}

function jotpinBuildDocument(sourceValue) {
  var source = String(sourceValue || '')
  var metrics = {fullScan: true, parsedLineCount: 0,
    reusedLineCount: 0, checkedCandidateCount: 0}
  var lines = []
  var start = 0
  var state = ''
  do {
    var end = jotpinLineEnd(source, start)
    var entry = jotpinBuildLineEntry(source.slice(start, end), state, metrics)
    entry.start = start
    lines.push(entry)
    state = entry.stateAfter
    start = end
  } while (start < source.length)
  jotpinCachedSource = source
  jotpinCachedLines = lines
  jotpinDocumentInitialized = true
  return metrics
}

function jotpinLineIndexAt(positionValue) {
  var position = Math.max(0, Math.min(jotpinCachedSource.length,
    Number(positionValue) || 0))
  var low = 0
  var high = jotpinCachedLines.length - 1
  while (low <= high) {
    var index = Math.floor((low + high) / 2)
    var line = jotpinCachedLines[index] || {}
    var start = Number(line.start) || 0
    var end = start + String(line.text || '').length
    if (position < start) high = index - 1
    else if (position >= end && index < jotpinCachedLines.length - 1)
      low = index + 1
    else return index
  }
  return Math.max(0, Math.min(jotpinCachedLines.length - 1, low))
}

function jotpinApplyPatch(patchValue, metrics) {
  var patch = patchValue || {}
  var start = Math.max(0, Math.min(jotpinCachedSource.length,
    Number(patch.start) || 0))
  var removed = String(patch.removed || '')
  var inserted = String(patch.inserted || '')
  if (jotpinCachedSource.slice(start, start + removed.length) !== removed)
    return false

  var oldLines = jotpinCachedLines
  var startLineIndex = jotpinLineIndexAt(start)
  var oldEndPosition = removed.length > 0
    ? start + removed.length - 1 : start
  var oldEndLineIndex = jotpinLineIndexAt(oldEndPosition)
  var oldResumeIndex = oldEndLineIndex + 1
  var rebuildStart = Number(oldLines[startLineIndex].start) || 0
  var nextSource = jotpinCachedSource.slice(0, start) + inserted +
    jotpinCachedSource.slice(start + removed.length)
  var newEndPosition = inserted.length > 0
    ? start + inserted.length - 1 : start
  var newResumeOffset = jotpinLineEnd(nextSource, newEndPosition)
  var nextLines = oldLines.slice(0, startLineIndex)
  var state = nextLines.length > 0
    ? String(nextLines[nextLines.length - 1].stateAfter || '') : ''
  var cursor = rebuildStart
  var oldIndex = oldResumeIndex
  var reusedSuffix = false

  do {
    var lineEnd = jotpinLineEnd(nextSource, cursor)
    var text = nextSource.slice(cursor, lineEnd)
    var aligningOldLine = cursor >= newResumeOffset
    if (aligningOldLine && oldIndex < oldLines.length) {
      var oldLine = oldLines[oldIndex] || {}
      if (String(oldLine.text || '') === text &&
          String(oldLine.stateBefore || '') === state &&
          Number(oldLine.dictionaryRevision) === jotpinDictionaryRevision) {
        for (var suffixIndex = oldIndex; suffixIndex < oldLines.length;
             suffixIndex++) nextLines.push(oldLines[suffixIndex])
        metrics.reusedLineCount += oldLines.length - oldIndex
        reusedSuffix = true
        break
      }
    }
    var entry = jotpinBuildLineEntry(text, state, metrics)
    nextLines.push(entry)
    state = entry.stateAfter
    cursor = lineEnd
    if (aligningOldLine && oldIndex < oldLines.length) oldIndex++
  } while (cursor < nextSource.length)

  if (!reusedSuffix && nextSource.length === 0 && nextLines.length === 0)
    nextLines.push(jotpinBuildLineEntry('', '', metrics))
  metrics.reusedLineCount += Math.max(0, startLineIndex)
  jotpinCachedSource = nextSource
  jotpinCachedLines = nextLines
  jotpinUpdateLineStarts()
  return true
}

function jotpinRefreshDictionaryResults(metrics) {
  for (var lineIndex = 0; lineIndex < jotpinCachedLines.length; lineIndex++) {
    var line = jotpinCachedLines[lineIndex] || {}
    if (Number(line.dictionaryRevision) === jotpinDictionaryRevision) continue
    var candidates = Array.isArray(line.candidates) ? line.candidates : []
    line.misspelled = new Array(candidates.length)
    for (var index = 0; index < candidates.length; index++) {
      line.misspelled[index] = jotpinWordMisspelled(candidates[index].word)
      metrics.checkedCandidateCount++
    }
    line.dictionaryRevision = jotpinDictionaryRevision
  }
}

function jotpinAssembleCachedResult(metrics) {
  jotpinRefreshDictionaryResults(metrics)
  var candidates = []
  var misspellings = []
  for (var lineIndex = 0; lineIndex < jotpinCachedLines.length; lineIndex++) {
    var line = jotpinCachedLines[lineIndex] || {}
    var localCandidates = Array.isArray(line.candidates) ? line.candidates : []
    var localMisspelled = Array.isArray(line.misspelled)
      ? line.misspelled : []
    for (var index = 0; index < localCandidates.length; index++) {
      var local = localCandidates[index] || {}
      var candidate = {word: String(local.word || ''),
        sourceWord: String(local.sourceWord || ''),
        start: Number(line.start) + (Number(local.start) || 0),
        end: Number(line.start) + (Number(local.end) || 0)}
      var candidateIndex = candidates.length
      candidates.push(candidate)
      if (localMisspelled[index]) misspellings.push({
        word: candidate.sourceWord,
        checkWord: candidate.word,
        start: candidate.start,
        end: candidate.end,
        candidateIndex: candidateIndex
      })
    }
  }
  metrics.totalLineCount = jotpinCachedLines.length
  metrics.totalCandidateCount = candidates.length
  return {candidates: candidates, misspellings: misspellings}
}

WorkerScript.onMessage = function(message) {
  var type = String(message.type || '')
  if (type === 'init') {
    jotpinSetPersonalWords(message.personalWords)
    jotpinEnsureChecker()
    WorkerScript.sendMessage({type: 'ready'})
    return
  }
  var checker = jotpinEnsureChecker()
  if (type === 'check') {
    var metrics = {fullScan: false, parsedLineCount: 0,
      reusedLineCount: 0, checkedCandidateCount: 0}
    if (!jotpinDocumentInitialized || message.full === true) {
      metrics = jotpinBuildDocument(message.source)
    } else {
      var edits = Array.isArray(message.edits) ? message.edits : []
      for (var editIndex = 0; editIndex < edits.length; editIndex++) {
        if (!jotpinApplyPatch(edits[editIndex], metrics)) {
          WorkerScript.sendMessage({type: 'resync',
            requestId: Number(message.requestId) || 0,
            sourceRevision: Number(message.sourceRevision) || 0})
          return
        }
      }
    }
    var result = jotpinAssembleCachedResult(metrics)
    WorkerScript.sendMessage({
      type: 'checked',
      requestId: Number(message.requestId) || 0,
      sourceRevision: Number(message.sourceRevision) || 0,
      candidates: result.candidates,
      misspellings: result.misspellings,
      metrics: metrics
    })
    return
  }
  if (type === 'suggest') {
    var suggestions = checker.suggest(String(message.word || '')).slice(0, 5)
    WorkerScript.sendMessage({
      type: 'suggestions',
      requestId: Number(message.requestId) || 0,
      suggestions: suggestions
    })
    return
  }
  if (type === 'ignore') {
    jotpinIgnoredWords[jotpinNormalizedWord(message.word)] = true
    jotpinDictionaryRevision++
    WorkerScript.sendMessage({type: 'wordChanged'})
    return
  }
  if (type === 'add') {
    var addedWord = String(message.word || '').trim()
    if (addedWord) {
      checker.add(addedWord)
      var normalizedAddedWord = jotpinNormalizedWord(addedWord)
      if (jotpinCorrectCache[normalizedAddedWord] === undefined)
        jotpinCorrectCacheSize++
      jotpinCorrectCache[normalizedAddedWord] = true
      jotpinDictionaryRevision++
    }
    WorkerScript.sendMessage({type: 'wordChanged', word: addedWord})
  }
}
