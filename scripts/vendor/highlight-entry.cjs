'use strict'

var hljs = require('highlight.js/lib/core')

var grammars = {
  bash: require('highlight.js/lib/languages/bash'),
  c: require('highlight.js/lib/languages/c'),
  cpp: require('highlight.js/lib/languages/cpp'),
  csharp: require('highlight.js/lib/languages/csharp'),
  clojure: require('highlight.js/lib/languages/clojure'),
  css: require('highlight.js/lib/languages/css'),
  dart: require('highlight.js/lib/languages/dart'),
  gdscript: require('@exercism/highlightjs-gdscript'),
  go: require('highlight.js/lib/languages/go'),
  graphql: require('highlight.js/lib/languages/graphql'),
  java: require('highlight.js/lib/languages/java'),
  javascript: require('highlight.js/lib/languages/javascript'),
  json: require('highlight.js/lib/languages/json'),
  kotlin: require('highlight.js/lib/languages/kotlin'),
  lua: require('highlight.js/lib/languages/lua'),
  markdown: require('highlight.js/lib/languages/markdown'),
  objectivec: require('highlight.js/lib/languages/objectivec'),
  perl: require('highlight.js/lib/languages/perl'),
  php: require('highlight.js/lib/languages/php'),
  powershell: require('highlight.js/lib/languages/powershell'),
  python: require('highlight.js/lib/languages/python'),
  qml: require('highlight.js/lib/languages/qml'),
  r: require('highlight.js/lib/languages/r'),
  ruby: require('highlight.js/lib/languages/ruby'),
  rust: require('highlight.js/lib/languages/rust'),
  scss: require('highlight.js/lib/languages/scss'),
  sql: require('highlight.js/lib/languages/sql'),
  swift: require('highlight.js/lib/languages/swift'),
  typescript: require('highlight.js/lib/languages/typescript'),
  xml: require('highlight.js/lib/languages/xml'),
  yaml: require('highlight.js/lib/languages/yaml')
}

Object.keys(grammars).forEach(function (name) {
  hljs.registerLanguage(name, grammars[name])
})

var aliases = {
  'c++': 'cpp', h: 'cpp', 'h++': 'cpp',
  'c#': 'csharp', cs: 'csharp',
  fish: 'bash', shell: 'bash', sh: 'bash', zsh: 'bash',
  gd: 'gdscript', golang: 'go',
  html: 'xml', svg: 'xml',
  js: 'javascript', jsx: 'javascript',
  jsonc: 'json', kt: 'kotlin',
  md: 'markdown', 'objective-c': 'objectivec', objc: 'objectivec',
  ps: 'powershell', py: 'python', rb: 'ruby', rs: 'rust',
  ts: 'typescript', tsx: 'typescript', yml: 'yaml'
}

var labels = {
  bash: 'Bash', c: 'C', cpp: 'C++', csharp: 'C#', clojure: 'Clojure',
  css: 'CSS', dart: 'Dart', gdscript: 'GDScript', go: 'Go',
  graphql: 'GraphQL', java: 'Java', javascript: 'JavaScript', json: 'JSON',
  kotlin: 'Kotlin', lua: 'Lua', markdown: 'Markdown',
  objectivec: 'Objective-C', perl: 'Perl', php: 'PHP',
  powershell: 'PowerShell', python: 'Python', qml: 'QML', r: 'R',
  ruby: 'Ruby', rust: 'Rust', scss: 'SCSS', sql: 'SQL', swift: 'Swift',
  typescript: 'TypeScript', xml: 'XML', yaml: 'YAML'
}

var darkColors = {
  keyword: '#ff7ab2', built_in: '#f7c06a', type: '#82d2ce', literal: '#c099ff',
  number: '#c099ff', operator: '#ff7ab2', punctuation: '#a8b2c1',
  property: '#82d2ce', regexp: '#ff8170', string: '#a8cc8c',
  char: '#a8cc8c', subst: '#e6edf3', symbol: '#f7c06a',
  variable: '#d2a8ff', variable_language: '#ff7ab2',
  variable_constant: '#c099ff', title: '#82d2ce', params: '#e6edf3',
  comment: '#7d8998', doctag: '#f7c06a', meta: '#d2a8ff',
  meta_keyword: '#ff7ab2', meta_string: '#a8cc8c', section: '#82d2ce',
  tag: '#ff7ab2', name: '#82d2ce', attr: '#f7c06a', attribute: '#f7c06a',
  bullet: '#f7c06a', code: '#a8cc8c', emphasis: '#e6edf3', strong: '#e6edf3',
  formula: '#82d2ce', link: '#79c0ff', quote: '#a8cc8c', selector_tag: '#ff7ab2',
  selector_id: '#82d2ce', selector_class: '#82d2ce',
  selector_attr: '#f7c06a', selector_pseudo: '#d2a8ff', template_tag: '#ff7ab2',
  template_variable: '#d2a8ff', addition: '#a8cc8c', deletion: '#ff8170'
}

var lightColors = {
  keyword: '#a626a4', built_in: '#986801', type: '#0184bc', literal: '#4078f2',
  number: '#4078f2', operator: '#a626a4', punctuation: '#52606d',
  property: '#0184bc', regexp: '#e45649', string: '#50a14f',
  char: '#50a14f', subst: '#24292f', symbol: '#986801',
  variable: '#a626a4', variable_language: '#a626a4',
  variable_constant: '#4078f2', title: '#0184bc', params: '#24292f',
  comment: '#6a737d', doctag: '#986801', meta: '#a626a4',
  meta_keyword: '#a626a4', meta_string: '#50a14f', section: '#0184bc',
  tag: '#a626a4', name: '#0184bc', attr: '#986801', attribute: '#986801',
  bullet: '#986801', code: '#50a14f', emphasis: '#24292f', strong: '#24292f',
  formula: '#0184bc', link: '#0366d6', quote: '#50a14f', selector_tag: '#a626a4',
  selector_id: '#0184bc', selector_class: '#0184bc',
  selector_attr: '#986801', selector_pseudo: '#a626a4', template_tag: '#a626a4',
  template_variable: '#a626a4', addition: '#50a14f', deletion: '#e45649'
}

function normalizeLanguage (value) {
  var token = String(value || '').trim().split(/\s+/)[0].replace(/^\./, '').toLowerCase()
  if (!token || /^(?:none|plain|text|txt)$/.test(token)) return ''
  return aliases[token] || token
}

function hasLanguage (value) {
  var language = normalizeLanguage(value)
  return Boolean(language && hljs.getLanguage(language))
}

function languageLabel (value) {
  var language = normalizeLanguage(value)
  return labels[language] || ''
}

function colorForClass (classValue, dark) {
  var colors = dark === false ? lightColors : darkColors
  var names = String(classValue || '').replace(/hljs-/g, '').split(/\s+/)
  for (var index = 0; index < names.length; index++) {
    var normalized = names[index].replace(/-/g, '_')
    if (colors[normalized]) return colors[normalized]
  }
  return ''
}

function qtMarkup (html, dark) {
  var markup = String(html || '').replace(/<span class="([^"]+)">/g,
    function (_, classValue) {
      var color = colorForClass(classValue, dark)
      return color ? '<font color="' + color + '">' : '<font>'
    }).replace(/<\/span>/g, '</font>')
  return markup.split(/(<[^>]+>)/).map(function (part) {
    if (part.charAt(0) === '<') return part
    return part.replace(/ {2,}/g, function (spaces) {
      return new Array(spaces.length + 1).join('&nbsp;')
    }).replace(/\t/g, '&nbsp;&nbsp;&nbsp;&nbsp;')
      .replace(/\n/g, '<br/>')
  }).join('')
}

function plainMarkup (code) {
  return String(code || '').replace(/&/g, '&amp;')
    .replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/ {2,}/g, function (spaces) {
      return new Array(spaces.length + 1).join('&nbsp;')
    }).replace(/\t/g, '&nbsp;&nbsp;&nbsp;&nbsp;')
      .replace(/\n/g, '<br/>')
}

function highlight (code, languageValue, dark) {
  var language = normalizeLanguage(languageValue)
  if (!language || !hljs.getLanguage(language)) return ''
  try {
    return qtMarkup(hljs.highlight(String(code || ''), {
      language: language,
      ignoreIllegals: true
    }).value, dark)
  } catch (_) {
    // A grammar incompatibility must never make the user's code disappear.
    return plainMarkup(code)
  }
}

module.exports = {
  hasLanguage: hasLanguage,
  highlight: highlight,
  languageLabel: languageLabel,
  normalizeLanguage: normalizeLanguage
}
