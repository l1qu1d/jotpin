function excludedMarkdownRanges(sourceValue) {
  var source = String(sourceValue || "")
  var ranges = []
  var lineStart = 0
  var inFence = false
  var fenceMarker = ""
  var fenceLength = 0

  while (lineStart <= source.length) {
    var newline = source.indexOf("\n", lineStart)
    var lineEnd = newline < 0 ? source.length : newline
    var line = source.slice(lineStart, lineEnd).replace(/\r$/, "")
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
      ranges.push({ start: lineStart, end: newline < 0 ? lineEnd : newline + 1 })
    } else if (inFence || /^ {4}\S/.test(line) || /^\[[^\]]+\]:\s*\S+/.test(line)) {
      ranges.push({ start: lineStart, end: newline < 0 ? lineEnd : newline + 1 })
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
            var labelEnd = match[0].indexOf("](")
            if (labelEnd >= 0) {
              var destinationStart = match.index + labelEnd + 1
              ranges.push({ start: lineStart + destinationStart,
                end: lineStart + match.index + match[0].length })
              continue
            }
          }
          ranges.push({ start: lineStart + match.index,
            end: lineStart + match.index + match[0].length })
        }
      }
    }
    if (newline < 0) break
    lineStart = newline + 1
  }
  ranges.sort(function(a, b) { return a.start - b.start || a.end - b.end })
  return ranges
}

function positionExcluded(position, ranges, state) {
  var index = state.index
  while (index < ranges.length && ranges[index].end <= position) index++
  state.index = index
  return index < ranges.length && position >= ranges[index].start &&
    position < ranges[index].end
}

function spellingCandidates(sourceValue) {
  var source = String(sourceValue || "")
  var exclusions = excludedMarkdownRanges(source)
  var state = { index: 0 }
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
    if (positionExcluded(start, exclusions, state)) continue
    var before = start > 0 ? source[start - 1] : ""
    var after = end < source.length ? source[end] : ""
    if (/[0-9_]/.test(before) || /[0-9_]/.test(after)) continue
    var normalized = match[0].replace(/’/g, "'")
    if (technicalWords[normalized.toLowerCase()] ||
        /[a-z][A-Z]/.test(normalized)) continue
    candidates.push({
      word: normalized,
      sourceWord: match[0],
      start: start,
      end: end
    })
  }
  return candidates
}

function withoutExcludedMarkdownRanges(sourceValue, rangesValue) {
  var source = String(sourceValue || "")
  var values = Array.isArray(rangesValue) ? rangesValue : []
  var exclusions = excludedMarkdownRanges(source)
  var result = []
  for (var valueIndex = 0; valueIndex < values.length; valueIndex++) {
    var value = values[valueIndex] || {}
    var start = Math.max(0, Number(value.start) || 0)
    var end = Math.max(start, Number(value.end) || start)
    var excluded = false
    for (var exclusionIndex = 0;
         exclusionIndex < exclusions.length; exclusionIndex++) {
      var exclusion = exclusions[exclusionIndex]
      if (exclusion.end <= start) continue
      if (exclusion.start >= end) break
      excluded = true
      break
    }
    if (!excluded && end > start && end <= source.length) result.push(value)
  }
  return result
}

function validatedMisspellings(candidatesValue, rangesValue) {
  var candidates = Array.isArray(candidatesValue) ? candidatesValue : []
  var ranges = Array.isArray(rangesValue) ? rangesValue : []
  var result = []
  for (var rangeIndex = 0; rangeIndex < ranges.length; rangeIndex++) {
    var range = ranges[rangeIndex] || {}
    var candidateIndex = Number(range.candidateIndex)
    if (!isFinite(candidateIndex) || candidateIndex < 0 ||
        Math.floor(candidateIndex) !== candidateIndex ||
        candidateIndex >= candidates.length) continue
    var candidate = candidates[candidateIndex] || {}
    var start = Number(range.start)
    var end = Number(range.end)
    if (!isFinite(start) || !isFinite(end) || end <= start ||
        start !== Number(candidate.start) || end !== Number(candidate.end) ||
        String(range.checkWord || '') !== String(candidate.word || '') ||
        String(range.word || '') !== String(candidate.sourceWord || ''))
      continue
    result.push(range)
  }
  return result
}

function candidateSequencesEqual(firstValue, secondValue) {
  var first = Array.isArray(firstValue) ? firstValue : []
  var second = Array.isArray(secondValue) ? secondValue : []
  if (first.length !== second.length) return false
  for (var index = 0; index < first.length; index++) {
    if (String(first[index].word || '') !== String(second[index].word || '') ||
        String(first[index].sourceWord || '') !==
          String(second[index].sourceWord || '')) return false
  }
  return true
}

function rebaseMisspellings(previousCandidatesValue, nextCandidatesValue,
    rangesValue) {
  var previousCandidates = Array.isArray(previousCandidatesValue)
    ? previousCandidatesValue : []
  var nextCandidates = Array.isArray(nextCandidatesValue)
    ? nextCandidatesValue : []
  var ranges = Array.isArray(rangesValue) ? rangesValue : []
  if (!candidateSequencesEqual(previousCandidates, nextCandidates)) return null
  var rebased = []
  for (var rangeIndex = 0; rangeIndex < ranges.length; rangeIndex++) {
    var range = ranges[rangeIndex] || {}
    var candidateIndex = Number(range.candidateIndex)
    if (!isFinite(candidateIndex) || candidateIndex < 0 ||
        candidateIndex >= previousCandidates.length) return null
    candidateIndex = Math.floor(candidateIndex)
    var previous = previousCandidates[candidateIndex] || {}
    var next = nextCandidates[candidateIndex] || {}
    if (Number(previous.start) !== Number(range.start) ||
        Number(previous.end) !== Number(range.end)) return null
    var updated = Object.assign({}, range)
    updated.word = String(next.sourceWord || range.word || '')
    updated.start = Number(next.start) || 0
    updated.end = Number(next.end) || updated.start
    updated.candidateIndex = candidateIndex
    rebased.push(updated)
  }
  return rebased
}

function rangeAtPosition(rangesValue, positionValue) {
  var ranges = Array.isArray(rangesValue) ? rangesValue : []
  var position = Number(positionValue)
  for (var index = 0; index < ranges.length; index++) {
    var range = ranges[index]
    if (position >= Number(range.start) && position < Number(range.end))
      return range
  }
  return null
}

// Derive the smallest contiguous UTF-16 edit that transforms one source into
// another.  The returned offsets are suitable for the editor/WorkerScript
// patch protocol and preserve CRLF bytes because only matching prefix/suffix
// characters are skipped.
function deriveSpellcheckEdit(previousSourceValue, nextSourceValue) {
  var previousSource = String(previousSourceValue || "")
  var nextSource = String(nextSourceValue || "")
  var prefix = 0
  var prefixLimit = Math.min(previousSource.length, nextSource.length)
  while (prefix < prefixLimit &&
      previousSource.charAt(prefix) === nextSource.charAt(prefix)) prefix++

  var suffix = 0
  var previousRemaining = previousSource.length - prefix
  var nextRemaining = nextSource.length - prefix
  while (suffix < previousRemaining && suffix < nextRemaining &&
      previousSource.charAt(previousSource.length - 1 - suffix) ===
        nextSource.charAt(nextSource.length - 1 - suffix)) suffix++

  return {
    start: prefix,
    deletedLength: previousSource.length - prefix - suffix,
    insertedText: nextSource.slice(prefix, nextSource.length - suffix),
    oldEnd: previousSource.length - suffix,
    newEnd: nextSource.length - suffix,
    delta: nextSource.length - previousSource.length
  }
}

if (typeof module !== "undefined") module.exports = {
  excludedMarkdownRanges: excludedMarkdownRanges,
  spellingCandidates: spellingCandidates,
  withoutExcludedMarkdownRanges: withoutExcludedMarkdownRanges,
  validatedMisspellings: validatedMisspellings,
  candidateSequencesEqual: candidateSequencesEqual,
  rebaseMisspellings: rebaseMisspellings,
  rangeAtPosition: rangeAtPosition,
  deriveSpellcheckEdit: deriveSpellcheckEdit
}
