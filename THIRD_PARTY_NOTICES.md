# Third-party notices

## HTML named character reference data

`HtmlEntities.js` is a generated lookup table. The repository script
`scripts/generate_html_entities.py` produces it from Python's standard-library
`html.entities.html5` mapping, whose definitions follow the HTML Living
Standard's named character references.

Python and its standard library are distributed under the Python Software
Foundation License Version 2. The license text and Python's bundled-license
history are published in the
[Python documentation](https://docs.python.org/3/license.html).

The generated table is included so JotPin can decode Markdown character
references locally at runtime. JotPin does not import Python or contact an
external service while running.

## Bundled spellcheck

JotPin's generated spellcheck worker includes `nspell` 2.1.5 and
`dictionary-en` 4.0.0. The dictionary supplies the English (US) Hunspell data.
The worker runs locally and does not contact an operating-system spelling
service or a network service.

- `nspell` is distributed under the MIT License. The complete notice is in
  `vendor/licenses/nspell-MIT.txt`.
- `nspell` includes `is-buffer`, distributed under the MIT License. The
  complete notice is in `vendor/licenses/is-buffer-MIT.txt`.
- `dictionary-en` is distributed under the MIT and BSD terms included in
  `vendor/licenses/dictionary-en-MIT-BSD.txt`.

## Bundled syntax highlighting

JotPin's generated syntax worker includes Highlight.js 11.12.0 and the
`@exercism/highlightjs-gdscript` 0.0.1 language definition. Only JotPin's
curated language set is registered; unknown fenced-code language names remain
readable plain code.

- Highlight.js is distributed under the BSD 3-Clause License. The complete
  notice is in `vendor/licenses/highlight.js-BSD-3-Clause.txt`.
- The GDScript package's distributed license text is included unchanged in
  `vendor/licenses/highlightjs-gdscript-MIT.txt`.

## Bundled Markdown parser

JotPin's generated Markdown worker includes micromark 4.0.2,
micromark-extension-gfm 3.0.0, mdast-util-from-markdown 2.0.3,
mdast-util-gfm 3.1.0, mdast-util-to-hast 13.2.1,
hast-util-sanitize 5.0.2, and hast-util-to-html 9.0.5 with their
unified/syntax-tree utility dependencies. The worker parses locally, sanitizes
the generated structural HTML, and sends it with a compact, source-positioned
syntax tree to QML; it does not contact a network service.

These packages and their bundled utility dependencies are distributed under
the MIT License. Their shared complete notice is in
`vendor/licenses/micromark-mdast-MIT.txt`.

Exact bundled versions are recorded in `vendor/VERSIONS.json`. Maintainers can
reproduce the generated workers from the pinned dependencies with:

```bash
npm ci --prefix scripts/vendor
node scripts/build_vendor_bundles.mjs
node scripts/build_markdown_bundle.mjs
```

Neither npm nor these build dependencies are used at JotPin runtime.
