import dictionaryPart1 from './DictionaryPart1.mjs'
import dictionaryPart2 from './DictionaryPart2.mjs'
var JOTPIN_NSPELL_BUNDLE = "var JotPinNSpell\n(function(f){if(typeof exports===\"object\"&&typeof module!==\"undefined\"){module.exports=f()}else if(typeof define===\"function\"&&define.amd){define([],f)}else{var g;if(typeof window!==\"undefined\"){g=window}else if(typeof global!==\"undefined\"){g=global}else if(typeof self!==\"undefined\"){g=self}else{g=this}JotPinNSpell = f()}})(function(){var define,module,exports;return (function(){function r(e,n,t){var u,i;function o(i,f){if(!n[i]){if(!e[i]){var c=\"function\"==typeof require&&require;if(!f&&c)return c(i,!0);if(u)return u(i,!0);var a=new Error(\"Cannot find module '\"+i+\"'\");throw a.code=\"MODULE_NOT_FOUND\",a}var p=n[i]={exports:{}};e[i][0].call(p.exports,function(r){var n=e[i][1][r];return o(n||r)},p,p.exports,r,e,n,t)}return n[i].exports}for(u=\"function\"==typeof require&&require,i=0;i<t.length;i++)o(t[i]);return o}return r})()({1:[function(require,module,exports){\n'use strict'\n\nvar push = require('./util/add.js')\n\nmodule.exports = add\n\nvar NO_CODES = []\n\n// Add `value` to the checker.\nfunction add(value, model) {\n  var self = this\n\n  push(self.data, value, self.data[model] || NO_CODES, self)\n\n  return self\n}\n\n},{\"./util/add.js\":9}],2:[function(require,module,exports){\n'use strict'\n\nvar form = require('./util/form.js')\n\nmodule.exports = correct\n\n// Check spelling of `value`.\nfunction correct(value) {\n  return Boolean(form(this, value))\n}\n\n},{\"./util/form.js\":16}],3:[function(require,module,exports){\n'use strict'\n\nvar parse = require('./util/dictionary.js')\n\nmodule.exports = add\n\n// Add a dictionary file.\nfunction add(buf) {\n  var self = this\n  var index = -1\n  var rule\n  var source\n  var character\n  var offset\n\n  parse(buf, self, self.data)\n\n  // Regenerate compound expressions.\n  while (++index < self.compoundRules.length) {\n    rule = self.compoundRules[index]\n    source = ''\n    offset = -1\n\n    while (++offset < rule.length) {\n      character = rule.charAt(offset)\n      source += self.compoundRuleCodes[character].length\n        ? '(?:' + self.compoundRuleCodes[character].join('|') + ')'\n        : character\n    }\n\n    self.compoundRules[index] = new RegExp(source, 'i')\n  }\n\n  return self\n}\n\n},{\"./util/dictionary.js\":13}],4:[function(require,module,exports){\n'use strict'\n\nvar buffer = require('is-buffer')\nvar affix = require('./util/affix.js')\n\nmodule.exports = NSpell\n\nvar proto = NSpell.prototype\n\nproto.correct = require('./correct.js')\nproto.suggest = require('./suggest.js')\nproto.spell = require('./spell.js')\nproto.add = require('./add.js')\nproto.remove = require('./remove.js')\nproto.wordCharacters = require('./word-characters.js')\nproto.dictionary = require('./dictionary.js')\nproto.personal = require('./personal.js')\n\n// Construct a new spelling context.\nfunction NSpell(aff, dic) {\n  var index = -1\n  var dictionaries\n\n  if (!(this instanceof NSpell)) {\n    return new NSpell(aff, dic)\n  }\n\n  if (typeof aff === 'string' || buffer(aff)) {\n    if (typeof dic === 'string' || buffer(dic)) {\n      dictionaries = [{dic: dic}]\n    }\n  } else if (aff) {\n    if ('length' in aff) {\n      dictionaries = aff\n      aff = aff[0] && aff[0].aff\n    } else {\n      if (aff.dic) {\n        dictionaries = [aff]\n      }\n\n      aff = aff.aff\n    }\n  }\n\n  if (!aff) {\n    throw new Error('Missing `aff` in dictionary')\n  }\n\n  aff = affix(aff)\n\n  this.data = Object.create(null)\n  this.compoundRuleCodes = aff.compoundRuleCodes\n  this.replacementTable = aff.replacementTable\n  this.conversion = aff.conversion\n  this.compoundRules = aff.compoundRules\n  this.rules = aff.rules\n  this.flags = aff.flags\n\n  if (dictionaries) {\n    while (++index < dictionaries.length) {\n      if (dictionaries[index].dic) {\n        this.dictionary(dictionaries[index].dic)\n      }\n    }\n  }\n}\n\n},{\"./add.js\":1,\"./correct.js\":2,\"./dictionary.js\":3,\"./personal.js\":5,\"./remove.js\":6,\"./spell.js\":7,\"./suggest.js\":8,\"./util/affix.js\":10,\"./word-characters.js\":19,\"is-buffer\":20}],5:[function(require,module,exports){\n'use strict'\n\nmodule.exports = add\n\n// Add a dictionary.\nfunction add(buf) {\n  var self = this\n  var lines = buf.toString('utf8').split('\\n')\n  var index = -1\n  var line\n  var forbidden\n  var word\n  var flag\n\n  // Ensure there’s a key for `FORBIDDENWORD`: `false` cannot be set through an\n  // affix file so its safe to use as a magic constant.\n  if (self.flags.FORBIDDENWORD === undefined) self.flags.FORBIDDENWORD = false\n  flag = self.flags.FORBIDDENWORD\n\n  while (++index < lines.length) {\n    line = lines[index].trim()\n\n    if (!line) {\n      continue\n    }\n\n    line = line.split('/')\n    word = line[0]\n    forbidden = word.charAt(0) === '*'\n\n    if (forbidden) {\n      word = word.slice(1)\n    }\n\n    self.add(word, line[1])\n\n    if (forbidden) {\n      self.data[word].push(flag)\n    }\n  }\n\n  return self\n}\n\n},{}],6:[function(require,module,exports){\n'use strict'\n\nmodule.exports = remove\n\n// Remove `value` from the checker.\nfunction remove(value) {\n  var self = this\n\n  delete self.data[value]\n\n  return self\n}\n\n},{}],7:[function(require,module,exports){\n'use strict'\n\nvar form = require('./util/form.js')\nvar flag = require('./util/flag.js')\n\nmodule.exports = spell\n\n// Check spelling of `word`.\nfunction spell(word) {\n  var self = this\n  var value = form(self, word, true)\n\n  // Hunspell also provides `root` (root word of the input word), and `compound`\n  // (whether `word` was compound).\n  return {\n    correct: self.correct(word),\n    forbidden: Boolean(\n      value && flag(self.flags, 'FORBIDDENWORD', self.data[value])\n    ),\n    warn: Boolean(value && flag(self.flags, 'WARN', self.data[value]))\n  }\n}\n\n},{\"./util/flag.js\":15,\"./util/form.js\":16}],8:[function(require,module,exports){\n'use strict'\n\nvar casing = require('./util/casing.js')\nvar normalize = require('./util/normalize.js')\nvar flag = require('./util/flag.js')\nvar form = require('./util/form.js')\n\nmodule.exports = suggest\n\nvar push = [].push\n\n// Suggest spelling for `value`.\n// eslint-disable-next-line complexity\nfunction suggest(value) {\n  var self = this\n  var charAdded = {}\n  var suggestions = []\n  var weighted = {}\n  var memory\n  var replacement\n  var edits = []\n  var values\n  var index\n  var offset\n  var position\n  var count\n  var otherOffset\n  var otherCharacter\n  var character\n  var group\n  var before\n  var after\n  var upper\n  var insensitive\n  var firstLevel\n  var previous\n  var next\n  var nextCharacter\n  var max\n  var distance\n  var size\n  var normalized\n  var suggestion\n  var currentCase\n\n  value = normalize(value.trim(), self.conversion.in)\n\n  if (!value || self.correct(value)) {\n    return []\n  }\n\n  currentCase = casing(value)\n\n  // Check the replacement table.\n  index = -1\n\n  while (++index < self.replacementTable.length) {\n    replacement = self.replacementTable[index]\n    offset = value.indexOf(replacement[0])\n\n    while (offset > -1) {\n      edits.push(value.replace(replacement[0], replacement[1]))\n      offset = value.indexOf(replacement[0], offset + 1)\n    }\n  }\n\n  // Check the keyboard.\n  index = -1\n\n  while (++index < value.length) {\n    character = value.charAt(index)\n    before = value.slice(0, index)\n    after = value.slice(index + 1)\n    insensitive = character.toLowerCase()\n    upper = insensitive !== character\n    charAdded = {}\n\n    offset = -1\n\n    while (++offset < self.flags.KEY.length) {\n      group = self.flags.KEY[offset]\n      position = group.indexOf(insensitive)\n\n      if (position < 0) {\n        continue\n      }\n\n      otherOffset = -1\n\n      while (++otherOffset < group.length) {\n        if (otherOffset !== position) {\n          otherCharacter = group.charAt(otherOffset)\n\n          if (charAdded[otherCharacter]) {\n            continue\n          }\n\n          charAdded[otherCharacter] = true\n\n          if (upper) {\n            otherCharacter = otherCharacter.toUpperCase()\n          }\n\n          edits.push(before + otherCharacter + after)\n        }\n      }\n    }\n  }\n\n  // Check cases where one of a double character was forgotten, or one too many\n  // were added, up to three “distances”.  This increases the success-rate by 2%\n  // and speeds the process up by 13%.\n  index = -1\n  nextCharacter = value.charAt(0)\n  values = ['']\n  max = 1\n  distance = 0\n\n  while (++index < value.length) {\n    character = nextCharacter\n    nextCharacter = value.charAt(index + 1)\n    before = value.slice(0, index)\n\n    replacement = character === nextCharacter ? '' : character + character\n    offset = -1\n    count = values.length\n\n    while (++offset < count) {\n      if (offset <= max) {\n        values.push(values[offset] + replacement)\n      }\n\n      values[offset] += character\n    }\n\n    if (++distance < 3) {\n      max = values.length\n    }\n  }\n\n  push.apply(edits, values)\n\n  // Ensure the capitalised and uppercase values are included.\n  values = [value]\n  replacement = value.toLowerCase()\n\n  if (value === replacement || currentCase === null) {\n    values.push(value.charAt(0).toUpperCase() + replacement.slice(1))\n  }\n\n  replacement = value.toUpperCase()\n\n  if (value !== replacement) {\n    values.push(replacement)\n  }\n\n  // Construct a memory object for `generate`.\n  memory = {\n    state: {},\n    weighted: weighted,\n    suggestions: suggestions\n  }\n\n  firstLevel = generate(self, memory, values, edits)\n\n  // While there are no suggestions based on generated values with an\n  // edit-distance of `1`, check the generated values, `SIZE` at a time.\n  // Basically, we’re generating values with an edit-distance of `2`, but were\n  // doing it in small batches because it’s such an expensive operation.\n  previous = 0\n  max = Math.min(firstLevel.length, Math.pow(Math.max(15 - value.length, 3), 3))\n  size = Math.max(Math.pow(10 - value.length, 3), 1)\n\n  while (!suggestions.length && previous < max) {\n    next = previous + size\n    generate(self, memory, firstLevel.slice(previous, next))\n    previous = next\n  }\n\n  // Sort the suggestions based on their weight.\n  suggestions.sort(sort)\n\n  // Normalize the output.\n  values = []\n  normalized = []\n  index = -1\n\n  while (++index < suggestions.length) {\n    suggestion = normalize(suggestions[index], self.conversion.out)\n    replacement = suggestion.toLowerCase()\n\n    if (normalized.indexOf(replacement) < 0) {\n      values.push(suggestion)\n      normalized.push(replacement)\n    }\n  }\n\n  // BOOM! All done!\n  return values\n\n  function sort(a, b) {\n    return sortWeight(a, b) || sortCasing(a, b) || sortAlpha(a, b)\n  }\n\n  function sortWeight(a, b) {\n    return weighted[a] === weighted[b] ? 0 : weighted[a] > weighted[b] ? -1 : 1\n  }\n\n  function sortCasing(a, b) {\n    var leftCasing = casing(a)\n    var rightCasing = casing(b)\n\n    return leftCasing === rightCasing\n      ? 0\n      : leftCasing === currentCase\n      ? -1\n      : rightCasing === currentCase\n      ? 1\n      : undefined\n  }\n\n  function sortAlpha(a, b) {\n    return a.localeCompare(b)\n  }\n}\n\n// Get a list of values close in edit distance to `words`.\nfunction generate(context, memory, words, edits) {\n  var characters = context.flags.TRY\n  var data = context.data\n  var flags = context.flags\n  var result = []\n  var index = -1\n  var word\n  var before\n  var character\n  var nextCharacter\n  var nextAfter\n  var nextNextAfter\n  var nextUpper\n  var currentCase\n  var position\n  var after\n  var upper\n  var inject\n  var offset\n\n  // Check the pre-generated edits.\n  if (edits) {\n    while (++index < edits.length) {\n      check(edits[index], true)\n    }\n  }\n\n  // Iterate over given word.\n  index = -1\n\n  while (++index < words.length) {\n    word = words[index]\n    before = ''\n    character = ''\n    nextCharacter = word.charAt(0)\n    nextAfter = word\n    nextNextAfter = word.slice(1)\n    nextUpper = nextCharacter.toLowerCase() !== nextCharacter\n    currentCase = casing(word)\n    position = -1\n\n    // Iterate over every character (including the end).\n    while (++position <= word.length) {\n      before += character\n      after = nextAfter\n      nextAfter = nextNextAfter\n      nextNextAfter = nextAfter.slice(1)\n      character = nextCharacter\n      nextCharacter = word.charAt(position + 1)\n      upper = nextUpper\n\n      if (nextCharacter) {\n        nextUpper = nextCharacter.toLowerCase() !== nextCharacter\n      }\n\n      if (nextAfter && upper !== nextUpper) {\n        // Remove.\n        check(before + switchCase(nextAfter))\n\n        // Switch.\n        check(\n          before +\n            switchCase(nextCharacter) +\n            switchCase(character) +\n            nextNextAfter\n        )\n      }\n\n      // Remove.\n      check(before + nextAfter)\n\n      // Switch.\n      if (nextAfter) {\n        check(before + nextCharacter + character + nextNextAfter)\n      }\n\n      // Iterate over all possible letters.\n      offset = -1\n\n      while (++offset < characters.length) {\n        inject = characters[offset]\n\n        // Try uppercase if the original character was uppercased.\n        if (upper && inject !== inject.toUpperCase()) {\n          if (currentCase !== 's') {\n            check(before + inject + after)\n            check(before + inject + nextAfter)\n          }\n\n          inject = inject.toUpperCase()\n\n          check(before + inject + after)\n          check(before + inject + nextAfter)\n        } else {\n          // Add and replace.\n          check(before + inject + after)\n          check(before + inject + nextAfter)\n        }\n      }\n    }\n  }\n\n  // Return the list of generated words.\n  return result\n\n  // Check and handle a generated value.\n  function check(value, double) {\n    var state = memory.state[value]\n    var corrected\n\n    if (state !== Boolean(state)) {\n      result.push(value)\n\n      corrected = form(context, value)\n      state = corrected && !flag(flags, 'NOSUGGEST', data[corrected])\n\n      memory.state[value] = state\n\n      if (state) {\n        memory.weighted[value] = double ? 10 : 0\n        memory.suggestions.push(value)\n      }\n    }\n\n    if (state) {\n      memory.weighted[value]++\n    }\n  }\n\n  function switchCase(fragment) {\n    var first = fragment.charAt(0)\n\n    return (\n      (first.toLowerCase() === first\n        ? first.toUpperCase()\n        : first.toLowerCase()) + fragment.slice(1)\n    )\n  }\n}\n\n},{\"./util/casing.js\":12,\"./util/flag.js\":15,\"./util/form.js\":16,\"./util/normalize.js\":17}],9:[function(require,module,exports){\n'use strict'\n\nvar apply = require('./apply.js')\n\nmodule.exports = add\n\nvar push = [].push\n\nvar NO_RULES = []\n\n// Add `rules` for `word` to the table.\nfunction addRules(dict, word, rules) {\n  var curr = dict[word]\n\n  // Some dictionaries will list the same word multiple times with different\n  // rule sets.\n  if (word in dict) {\n    if (curr === NO_RULES) {\n      dict[word] = rules.concat()\n    } else {\n      push.apply(curr, rules)\n    }\n  } else {\n    dict[word] = rules.concat()\n  }\n}\n\nfunction add(dict, word, codes, options) {\n  var position = -1\n  var rule\n  var offset\n  var subposition\n  var suboffset\n  var combined\n  var newWords\n  var otherNewWords\n\n  // Compound words.\n  if (\n    !('NEEDAFFIX' in options.flags) ||\n    codes.indexOf(options.flags.NEEDAFFIX) < 0\n  ) {\n    addRules(dict, word, codes)\n  }\n\n  while (++position < codes.length) {\n    rule = options.rules[codes[position]]\n\n    if (codes[position] in options.compoundRuleCodes) {\n      options.compoundRuleCodes[codes[position]].push(word)\n    }\n\n    if (rule) {\n      newWords = apply(word, rule, options.rules, [])\n      offset = -1\n\n      while (++offset < newWords.length) {\n        if (!(newWords[offset] in dict)) {\n          dict[newWords[offset]] = NO_RULES\n        }\n\n        if (rule.combineable) {\n          subposition = position\n\n          while (++subposition < codes.length) {\n            combined = options.rules[codes[subposition]]\n\n            if (\n              combined &&\n              combined.combineable &&\n              rule.type !== combined.type\n            ) {\n              otherNewWords = apply(\n                newWords[offset],\n                combined,\n                options.rules,\n                []\n              )\n              suboffset = -1\n\n              while (++suboffset < otherNewWords.length) {\n                if (!(otherNewWords[suboffset] in dict)) {\n                  dict[otherNewWords[suboffset]] = NO_RULES\n                }\n              }\n            }\n          }\n        }\n      }\n    }\n  }\n}\n\n},{\"./apply.js\":11}],10:[function(require,module,exports){\n'use strict'\n\nvar parse = require('./rule-codes.js')\n\nmodule.exports = affix\n\nvar push = [].push\n\n// Relative frequencies of letters in the English language.\nvar alphabet = 'etaoinshrdlcumwfgypbvkjxqz'.split('')\n\n// Expressions.\nvar whiteSpaceExpression = /\\s+/\n\n// Defaults.\nvar defaultKeyboardLayout = [\n  'qwertzuop',\n  'yxcvbnm',\n  'qaw',\n  'say',\n  'wse',\n  'dsx',\n  'sy',\n  'edr',\n  'fdc',\n  'dx',\n  'rft',\n  'gfv',\n  'fc',\n  'tgz',\n  'hgb',\n  'gv',\n  'zhu',\n  'jhn',\n  'hb',\n  'uji',\n  'kjm',\n  'jn',\n  'iko',\n  'lkm'\n]\n\n// Parse an affix file.\n// eslint-disable-next-line complexity\nfunction affix(doc) {\n  var rules = Object.create(null)\n  var compoundRuleCodes = Object.create(null)\n  var flags = Object.create(null)\n  var replacementTable = []\n  var conversion = {in: [], out: []}\n  var compoundRules = []\n  var aff = doc.toString('utf8')\n  var lines = []\n  var last = 0\n  var index = aff.indexOf('\\n')\n  var parts\n  var line\n  var ruleType\n  var count\n  var remove\n  var add\n  var source\n  var entry\n  var position\n  var rule\n  var value\n  var offset\n  var character\n\n  flags.KEY = []\n\n  // Process the affix buffer into a list of applicable lines.\n  while (index > -1) {\n    pushLine(aff.slice(last, index))\n    last = index + 1\n    index = aff.indexOf('\\n', last)\n  }\n\n  pushLine(aff.slice(last))\n\n  // Process each line.\n  index = -1\n\n  while (++index < lines.length) {\n    line = lines[index]\n    parts = line.split(whiteSpaceExpression)\n    ruleType = parts[0]\n\n    if (ruleType === 'REP') {\n      count = index + parseInt(parts[1], 10)\n\n      while (++index <= count) {\n        parts = lines[index].split(whiteSpaceExpression)\n        replacementTable.push([parts[1], parts[2]])\n      }\n\n      index--\n    } else if (ruleType === 'ICONV' || ruleType === 'OCONV') {\n      count = index + parseInt(parts[1], 10)\n      entry = conversion[ruleType === 'ICONV' ? 'in' : 'out']\n\n      while (++index <= count) {\n        parts = lines[index].split(whiteSpaceExpression)\n        entry.push([new RegExp(parts[1], 'g'), parts[2]])\n      }\n\n      index--\n    } else if (ruleType === 'COMPOUNDRULE') {\n      count = index + parseInt(parts[1], 10)\n\n      while (++index <= count) {\n        rule = lines[index].split(whiteSpaceExpression)[1]\n        position = -1\n\n        compoundRules.push(rule)\n\n        while (++position < rule.length) {\n          compoundRuleCodes[rule.charAt(position)] = []\n        }\n      }\n\n      index--\n    } else if (ruleType === 'PFX' || ruleType === 'SFX') {\n      count = index + parseInt(parts[3], 10)\n\n      rule = {\n        type: ruleType,\n        combineable: parts[2] === 'Y',\n        entries: []\n      }\n\n      rules[parts[1]] = rule\n\n      while (++index <= count) {\n        parts = lines[index].split(whiteSpaceExpression)\n        remove = parts[2]\n        add = parts[3].split('/')\n        source = parts[4]\n\n        entry = {\n          add: '',\n          remove: '',\n          match: '',\n          continuation: parse(flags, add[1])\n        }\n\n        if (add && add[0] !== '0') {\n          entry.add = add[0]\n        }\n\n        try {\n          if (remove !== '0') {\n            entry.remove = ruleType === 'SFX' ? end(remove) : remove\n          }\n\n          if (source && source !== '.') {\n            entry.match = ruleType === 'SFX' ? end(source) : start(source)\n          }\n        } catch (_) {\n          // Ignore invalid regex patterns.\n          entry = null\n        }\n\n        if (entry) {\n          rule.entries.push(entry)\n        }\n      }\n\n      index--\n    } else if (ruleType === 'TRY') {\n      source = parts[1]\n      offset = -1\n      value = []\n\n      while (++offset < source.length) {\n        character = source.charAt(offset)\n\n        if (character.toLowerCase() === character) {\n          value.push(character)\n        }\n      }\n\n      // Some dictionaries may forget a character.\n      // Notably `en` forgets `j`, `x`, and `y`.\n      offset = -1\n\n      while (++offset < alphabet.length) {\n        if (source.indexOf(alphabet[offset]) < 0) {\n          value.push(alphabet[offset])\n        }\n      }\n\n      flags[ruleType] = value\n    } else if (ruleType === 'KEY') {\n      push.apply(flags[ruleType], parts[1].split('|'))\n    } else if (ruleType === 'COMPOUNDMIN') {\n      flags[ruleType] = Number(parts[1])\n    } else if (ruleType === 'ONLYINCOMPOUND') {\n      // If we add this ONLYINCOMPOUND flag to `compoundRuleCodes`, then\n      // `parseDic` will do the work of saving the list of words that are\n      // compound-only.\n      flags[ruleType] = parts[1]\n      compoundRuleCodes[parts[1]] = []\n    } else if (\n      ruleType === 'FLAG' ||\n      ruleType === 'KEEPCASE' ||\n      ruleType === 'NOSUGGEST' ||\n      ruleType === 'WORDCHARS'\n    ) {\n      flags[ruleType] = parts[1]\n    } else {\n      // Default handling: set them for now.\n      flags[ruleType] = parts[1]\n    }\n  }\n\n  // Default for `COMPOUNDMIN` is `3`.\n  // See `man 4 hunspell`.\n  if (isNaN(flags.COMPOUNDMIN)) {\n    flags.COMPOUNDMIN = 3\n  }\n\n  if (!flags.KEY.length) {\n    flags.KEY = defaultKeyboardLayout\n  }\n\n  /* istanbul ignore if - Dictionaries seem to always have this. */\n  if (!flags.TRY) {\n    flags.TRY = alphabet.concat()\n  }\n\n  if (!flags.KEEPCASE) {\n    flags.KEEPCASE = false\n  }\n\n  return {\n    compoundRuleCodes: compoundRuleCodes,\n    replacementTable: replacementTable,\n    conversion: conversion,\n    compoundRules: compoundRules,\n    rules: rules,\n    flags: flags\n  }\n\n  function pushLine(line) {\n    line = line.trim()\n\n    // Hash can be a valid flag, so we only discard line that starts with it.\n    if (line && line.charCodeAt(0) !== 35 /* `#` */) {\n      lines.push(line)\n    }\n  }\n}\n\n// Wrap the `source` of an expression-like string so that it matches only at\n// the end of a value.\nfunction end(source) {\n  return new RegExp(source + '$')\n}\n\n// Wrap the `source` of an expression-like string so that it matches only at\n// the start of a value.\nfunction start(source) {\n  return new RegExp('^' + source)\n}\n\n},{\"./rule-codes.js\":18}],11:[function(require,module,exports){\n'use strict'\n\nmodule.exports = apply\n\n// Apply a rule.\nfunction apply(value, rule, rules, words) {\n  var index = -1\n  var entry\n  var next\n  var continuationRule\n  var continuation\n  var position\n\n  while (++index < rule.entries.length) {\n    entry = rule.entries[index]\n    continuation = entry.continuation\n    position = -1\n\n    if (!entry.match || entry.match.test(value)) {\n      next = entry.remove ? value.replace(entry.remove, '') : value\n      next = rule.type === 'SFX' ? next + entry.add : entry.add + next\n      words.push(next)\n\n      if (continuation && continuation.length) {\n        while (++position < continuation.length) {\n          continuationRule = rules[continuation[position]]\n\n          if (continuationRule) {\n            apply(next, continuationRule, rules, words)\n          }\n        }\n      }\n    }\n  }\n\n  return words\n}\n\n},{}],12:[function(require,module,exports){\n'use strict'\n\nmodule.exports = casing\n\n// Get the casing of `value`.\nfunction casing(value) {\n  var head = exact(value.charAt(0))\n  var rest = value.slice(1)\n\n  if (!rest) {\n    return head\n  }\n\n  rest = exact(rest)\n\n  if (head === rest) {\n    return head\n  }\n\n  if (head === 'u' && rest === 'l') {\n    return 's'\n  }\n\n  return null\n}\n\nfunction exact(value) {\n  return value === value.toLowerCase()\n    ? 'l'\n    : value === value.toUpperCase()\n    ? 'u'\n    : null\n}\n\n},{}],13:[function(require,module,exports){\n'use strict'\n\nvar parseCodes = require('./rule-codes.js')\nvar add = require('./add.js')\n\nmodule.exports = parse\n\n// Expressions.\nvar whiteSpaceExpression = /\\s/g\n\n// Parse a dictionary.\nfunction parse(buf, options, dict) {\n  // Parse as lines (ignoring the first line).\n  var value = buf.toString('utf8')\n  var last = value.indexOf('\\n') + 1\n  var index = value.indexOf('\\n', last)\n\n  while (index > -1) {\n    // Some dictionaries use tabs as comments.\n    if (value.charCodeAt(last) !== 9 /* `\\t` */) {\n      parseLine(value.slice(last, index), options, dict)\n    }\n\n    last = index + 1\n    index = value.indexOf('\\n', last)\n  }\n\n  parseLine(value.slice(last), options, dict)\n}\n\n// Parse a line in dictionary.\nfunction parseLine(line, options, dict) {\n  var slashOffset = line.indexOf('/')\n  var hashOffset = line.indexOf('#')\n  var codes = ''\n  var word\n  var result\n\n  // Find offsets.\n  while (\n    slashOffset > -1 &&\n    line.charCodeAt(slashOffset - 1) === 92 /* `\\` */\n  ) {\n    line = line.slice(0, slashOffset - 1) + line.slice(slashOffset)\n    slashOffset = line.indexOf('/', slashOffset)\n  }\n\n  // Handle hash and slash offsets.\n  // Note that hash can be a valid flag, so we should not just discard\n  // everything after it.\n  if (hashOffset > -1) {\n    if (slashOffset > -1 && slashOffset < hashOffset) {\n      word = line.slice(0, slashOffset)\n      whiteSpaceExpression.lastIndex = slashOffset + 1\n      result = whiteSpaceExpression.exec(line)\n      codes = line.slice(slashOffset + 1, result ? result.index : undefined)\n    } else {\n      word = line.slice(0, hashOffset)\n    }\n  } else if (slashOffset > -1) {\n    word = line.slice(0, slashOffset)\n    codes = line.slice(slashOffset + 1)\n  } else {\n    word = line\n  }\n\n  word = word.trim()\n\n  if (word) {\n    add(dict, word, parseCodes(options.flags, codes.trim()), options)\n  }\n}\n\n},{\"./add.js\":9,\"./rule-codes.js\":18}],14:[function(require,module,exports){\n'use strict'\n\nvar flag = require('./flag.js')\n\nmodule.exports = exact\n\n// Check spelling of `value`, exactly.\nfunction exact(context, value) {\n  var index = -1\n\n  if (context.data[value]) {\n    return !flag(context.flags, 'ONLYINCOMPOUND', context.data[value])\n  }\n\n  // Check if this might be a compound word.\n  if (value.length >= context.flags.COMPOUNDMIN) {\n    while (++index < context.compoundRules.length) {\n      if (context.compoundRules[index].test(value)) {\n        return true\n      }\n    }\n  }\n\n  return false\n}\n\n},{\"./flag.js\":15}],15:[function(require,module,exports){\n'use strict'\n\nmodule.exports = flag\n\n// Check whether a word has a flag.\nfunction flag(values, value, flags) {\n  return flags && value in values && flags.indexOf(values[value]) > -1\n}\n\n},{}],16:[function(require,module,exports){\n'use strict'\n\nvar normalize = require('./normalize.js')\nvar exact = require('./exact.js')\nvar flag = require('./flag.js')\n\nmodule.exports = form\n\n// Find a known form of `value`.\nfunction form(context, value, all) {\n  var normal = value.trim()\n  var alternative\n\n  if (!normal) {\n    return null\n  }\n\n  normal = normalize(normal, context.conversion.in)\n\n  if (exact(context, normal)) {\n    if (!all && flag(context.flags, 'FORBIDDENWORD', context.data[normal])) {\n      return null\n    }\n\n    return normal\n  }\n\n  // Try sentence case if the value is uppercase.\n  if (normal.toUpperCase() === normal) {\n    alternative = normal.charAt(0) + normal.slice(1).toLowerCase()\n\n    if (ignore(context.flags, context.data[alternative], all)) {\n      return null\n    }\n\n    if (exact(context, alternative)) {\n      return alternative\n    }\n  }\n\n  // Try lowercase.\n  alternative = normal.toLowerCase()\n\n  if (alternative !== normal) {\n    if (ignore(context.flags, context.data[alternative], all)) {\n      return null\n    }\n\n    if (exact(context, alternative)) {\n      return alternative\n    }\n  }\n\n  return null\n}\n\nfunction ignore(flags, dict, all) {\n  return (\n    flag(flags, 'KEEPCASE', dict) || all || flag(flags, 'FORBIDDENWORD', dict)\n  )\n}\n\n},{\"./exact.js\":14,\"./flag.js\":15,\"./normalize.js\":17}],17:[function(require,module,exports){\n'use strict'\n\nmodule.exports = normalize\n\n// Normalize `value` with patterns.\nfunction normalize(value, patterns) {\n  var index = -1\n\n  while (++index < patterns.length) {\n    value = value.replace(patterns[index][0], patterns[index][1])\n  }\n\n  return value\n}\n\n},{}],18:[function(require,module,exports){\n'use strict'\n\nmodule.exports = ruleCodes\n\nvar NO_CODES = []\n\n// Parse rule codes.\nfunction ruleCodes(flags, value) {\n  var index = 0\n  var result\n\n  if (!value) return NO_CODES\n\n  if (flags.FLAG === 'long') {\n    // Creating an array of the right length immediately\n    // avoiding resizes and using memory more efficiently\n    result = new Array(Math.ceil(value.length / 2))\n\n    while (index < value.length) {\n      result[index / 2] = value.slice(index, index + 2)\n      index += 2\n    }\n\n    return result\n  }\n\n  return value.split(flags.FLAG === 'num' ? ',' : '')\n}\n\n},{}],19:[function(require,module,exports){\n'use strict'\n\nmodule.exports = wordCharacters\n\n// Get the word characters defined in affix.\nfunction wordCharacters() {\n  return this.flags.WORDCHARS || null\n}\n\n},{}],20:[function(require,module,exports){\n/*!\n * Determine if an object is a Buffer\n *\n * @author   Feross Aboukhadijeh <https://feross.org>\n * @license  MIT\n */\n\nmodule.exports = function isBuffer (obj) {\n  return obj != null && obj.constructor != null &&\n    typeof obj.constructor.isBuffer === 'function' && obj.constructor.isBuffer(obj)\n}\n\n},{}],21:[function(require,module,exports){\n'use strict'\n\nmodule.exports = require('nspell')\n\n},{\"nspell\":4}]},{},[21])(21)\n});\n"
var JOTPIN_AFF = "SET UTF-8\nTRY esianrtolcdugmphbyfvkwzESIANRTOLCDUGMPHBYFVKWZ'\nICONV 1\nICONV ’ '\nNOSUGGEST !\n\n# ordinal numbers\nCOMPOUNDMIN 1\n# only in compounds: 1th, 2th, 3th\nONLYINCOMPOUND c\n# compound rules:\n# 1. [0-9]*1[0-9]th (10th, 11th, 12th, 56714th, etc.)\n# 2. [0-9]*[02-9](1st|2nd|3rd|[4-9]th) (21st, 22nd, 123rd, 1234th, etc.)\nCOMPOUNDRULE 2\nCOMPOUNDRULE n*1t\nCOMPOUNDRULE n*mp\nWORDCHARS 0123456789\n\nPFX A Y 1\nPFX A   0     re         .\n\nPFX I Y 1\nPFX I   0     in         .\n\nPFX U Y 1\nPFX U   0     un         .\n\nPFX C Y 1\nPFX C   0     de          .\n\nPFX E Y 1\nPFX E   0     dis         .\n\nPFX F Y 1\nPFX F   0     con         .\n\nPFX K Y 1\nPFX K   0     pro         .\n\nSFX V N 2\nSFX V   e     ive        e\nSFX V   0     ive        [^e]\n\nSFX N Y 3\nSFX N   e     ion        e\nSFX N   y     ication    y\nSFX N   0     en         [^ey]\n\nSFX X Y 3\nSFX X   e     ions       e\nSFX X   y     ications   y\nSFX X   0     ens        [^ey]\n\nSFX H N 2\nSFX H   y     ieth       y\nSFX H   0     th         [^y]\n\nSFX Y Y 1\nSFX Y   0     ly         .\n\nSFX G Y 2\nSFX G   e     ing        e\nSFX G   0     ing        [^e]\n\nSFX J Y 2\nSFX J   e     ings       e\nSFX J   0     ings       [^e]\n\nSFX D Y 4\nSFX D   0     d          e\nSFX D   y     ied        [^aeiou]y\nSFX D   0     ed         [^ey]\nSFX D   0     ed         [aeiou]y\n\nSFX T N 4\nSFX T   0     st         e\nSFX T   y     iest       [^aeiou]y\nSFX T   0     est        [aeiou]y\nSFX T   0     est        [^ey]\n\nSFX R Y 4\nSFX R   0     r          e\nSFX R   y     ier        [^aeiou]y\nSFX R   0     er         [aeiou]y\nSFX R   0     er         [^ey]\n\nSFX Z Y 4\nSFX Z   0     rs         e\nSFX Z   y     iers       [^aeiou]y\nSFX Z   0     ers        [aeiou]y\nSFX Z   0     ers        [^ey]\n\nSFX S Y 4\nSFX S   y     ies        [^aeiou]y\nSFX S   0     s          [aeiou]y\nSFX S   0     es         [sxzh]\nSFX S   0     s          [^sxzhy]\n\nSFX P Y 3\nSFX P   y     iness      [^aeiou]y\nSFX P   0     ness       [aeiou]y\nSFX P   0     ness       [^y]\n\nSFX M Y 1\nSFX M   0     's         .\n\nSFX B Y 3\nSFX B   0     able       [^aeiou]\nSFX B   0     able       ee\nSFX B   e     able       [^aeiou]e\n\nSFX L Y 1\nSFX L   0     ment       .\n\nREP 90\nREP a ei\nREP ei a\nREP a ey\nREP ey a\nREP ai ie\nREP ie ai\nREP alot a_lot\nREP are air\nREP are ear\nREP are eir\nREP air are\nREP air ere\nREP ere air\nREP ere ear\nREP ere eir\nREP ear are\nREP ear air\nREP ear ere\nREP eir are\nREP eir ere\nREP ch te\nREP te ch\nREP ch ti\nREP ti ch\nREP ch tu\nREP tu ch\nREP ch s\nREP s ch\nREP ch k\nREP k ch\nREP f ph\nREP ph f\nREP gh f\nREP f gh\nREP i igh\nREP igh i\nREP i uy\nREP uy i\nREP i ee\nREP ee i\nREP j di\nREP di j\nREP j gg\nREP gg j\nREP j ge\nREP ge j\nREP s ti\nREP ti s\nREP s ci\nREP ci s\nREP k cc\nREP cc k\nREP k qu\nREP qu k\nREP kw qu\nREP o eau\nREP eau o\nREP o ew\nREP ew o\nREP oo ew\nREP ew oo\nREP ew ui\nREP ui ew\nREP oo ui\nREP ui oo\nREP ew u\nREP u ew\nREP oo u\nREP u oo\nREP u oe\nREP oe u\nREP u ieu\nREP ieu u\nREP ue ew\nREP ew ue\nREP uff ough\nREP oo ieu\nREP ieu oo\nREP ier ear\nREP ear ier\nREP ear air\nREP air ear\nREP w qu\nREP qu w\nREP z ss\nREP ss z\nREP shun tion\nREP shun sion\nREP shun cion\nREP size cise\n"
var JOTPIN_DIC = dictionaryPart1 + dictionaryPart2
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
