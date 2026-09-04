var languageAliases = {
  "c++": "cpp", "h": "cpp", "h++": "cpp",
  "c#": "csharp", "cs": "csharp",
  "fish": "bash", "shell": "bash", "sh": "bash", "zsh": "bash",
  "gd": "gdscript", "golang": "go",
  "html": "xml", "svg": "xml",
  "js": "javascript", "jsx": "javascript",
  "jsonc": "json", "kt": "kotlin",
  "md": "markdown", "objective-c": "objectivec", "objc": "objectivec",
  "ps": "powershell", "py": "python", "rb": "ruby", "rs": "rust",
  "ts": "typescript", "tsx": "typescript", "yml": "yaml"
}

var languageLabels = {
  bash: "Bash", c: "C", cpp: "C++", csharp: "C#", clojure: "Clojure",
  css: "CSS", dart: "Dart", gdscript: "GDScript", go: "Go",
  graphql: "GraphQL", java: "Java", javascript: "JavaScript", json: "JSON",
  kotlin: "Kotlin", lua: "Lua", markdown: "Markdown",
  objectivec: "Objective-C", perl: "Perl", php: "PHP",
  powershell: "PowerShell", python: "Python", qml: "QML", r: "R",
  ruby: "Ruby", rust: "Rust", scss: "SCSS", sql: "SQL", swift: "Swift",
  typescript: "TypeScript", xml: "XML", yaml: "YAML"
}

function normalizeLanguage(value) {
  var token = String(value || "").trim().split(/\s+/)[0]
    .replace(/^\./, "").toLowerCase()
  if (!token || /^(?:none|plain|text|txt)$/.test(token)) return ""
  return languageAliases[token] || token
}

function hasLanguage(value) {
  var language = normalizeLanguage(value)
  return Boolean(language && languageLabels[language])
}

function languageLabel(value) {
  return languageLabels[normalizeLanguage(value)] || ""
}

if (typeof module !== "undefined") module.exports = {
  normalizeLanguage: normalizeLanguage,
  hasLanguage: hasLanguage,
  languageLabel: languageLabel
}
