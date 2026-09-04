// Deliberately break disposable copies to prove that the acceptance tests
// detect the failures they claim to cover. Never modify the working checkout.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'jotpin-link-mutants-'));
const source = fs.readFileSync(path.join(root, 'NativeMarkdownDisplay.qml'), 'utf8');
const productSource = fs.readFileSync(path.join(root, 'JotPin.qml'), 'utf8');
const mutations = [
  {name: 'all links disabled', from: 'function linkTargetForPoint(localX, localY) {',
    to: 'function linkTargetForPoint(localX, localY) { return "";',
    failure: 'NativeLinkContract::test_link_contract(inline)'},
  {name: 'padding coordinate drift', from: 'x - nativeDocument.leftPadding - nativeDocument.topPadding,',
    to: 'x,', failure: 'NativeLinkContract::test_link_contract(inline)'},
  {name: 'blank space activates a link', from: 'function linkTargetForPoint(localX, localY) {',
    to: 'function linkTargetForPoint(localX, localY) { return "https://google.com";',
    failure: 'NativeMarkdownMouseBelowFence::test_ctrl_link_blank_space_is_inert()'},
  {name: 'plain clicks open links', from: 'if (mouse.modifiers & Qt.ControlModifier) {',
    to: 'if (true) {', secondFrom: '(mouse.modifiers & Qt.ControlModifier)) {',
    secondTo: 'true) {',
    failure: 'NativeMarkdownMouseBelowFence::test_ctrl_click_activates_link_only_with_modifier()'},
  {name: 'Ctrl marker disappears', from: 'visible: root.linkPointerMarkerVisible',
    to: 'visible: false',
    failure: 'NativeLinkContract::test_marker_pixels()'},
  {name: 'drag out and back opens a link', from: 'root.pendingLinkPressMoved = true',
    to: 'root.pendingLinkPressMoved = false',
    failure: 'NativeLinkContract::test_modifier_and_drag_boundaries()'},
  {name: 'product ignores Ctrl key press', product: true,
    from: 'root.controlKeyHeld = true', to: 'root.controlKeyHeld = false', occurrences: 2,
    failure: 'a real Qt Ctrl key press reaches JotPin'},
  {name: 'product drops URL dispatch', product: true,
    from: 'root.externalUrlOpener(target)', to: 'void target',
    failure: 'a real Ctrl+click reaches the product URL opener once'}
];
function replaceOnce(text, from, to, occurrences = 1) {
  assert.equal(text.split(from).length, occurrences + 1, `mutation target count changed: ${from}`);
  return text.split(from).join(to);
}
try {
  for (const entry of ['EditorModel.js', 'SyntaxHighlight.js', 'markdown', 'syntax',
    'JotPinButton.qml', 'HostIntegration.qml', 'HtmlEntities.js', 'SpellcheckModel.js',
    'spellcheck', 'assets'])
    fs.cpSync(path.join(root, entry), path.join(temporary, entry), {recursive: true});
  fs.mkdirSync(path.join(temporary, 'tests/isolated'), {recursive: true});
  fs.mkdirSync(path.join(temporary, 'tests/fixtures'), {recursive: true});
  for (const entry of ['native_markdown_mouse_regression.sh', 'check_qt_contracts.cjs',
    'qt_contracts.json', 'isolated/tst_native_markdown_mouse.qml',
    'isolated/tst_native_link_contract.qml', 'fixtures/markdown-image.svg',
    'jotpin_link_keys_regression.sh', 'isolated/jotpin_link_keys.qml',
    'fixtures/persistence-base.md'])
    fs.copyFileSync(path.join(__dirname, entry), path.join(temporary, 'tests', entry));
  for (const mutation of mutations) {
    let modified = replaceOnce(mutation.product ? productSource : source,
      mutation.from, mutation.to, mutation.occurrences);
    if (mutation.secondFrom)
      modified = replaceOnce(modified, mutation.secondFrom, mutation.secondTo);
    fs.writeFileSync(path.join(temporary, 'NativeMarkdownDisplay.qml'), mutation.product ? source : modified);
    fs.writeFileSync(path.join(temporary, 'JotPin.qml'), mutation.product ? modified : productSource);
    const runner = mutation.product ? 'jotpin_link_keys_regression.sh' : 'native_markdown_mouse_regression.sh';
    const result = spawnSync('bash', [path.join(temporary, 'tests', runner)],
      {encoding: 'utf8', timeout: 40000, maxBuffer: 4 * 1024 * 1024});
    const output = String(result.stdout || '') + String(result.stderr || '');
    assert.equal(result.error, undefined, `mutation process error: ${mutation.name}`);
    assert.notEqual(result.status, 0, `tests accepted broken behavior: ${mutation.name}`);
    assert(output.split('\n').some(line =>
      (mutation.product ? line.includes('JOTPIN_LINK_KEYS_FAIL:') : line.startsWith('FAIL!')) &&
      line.includes(mutation.failure)),
      `mutation must fail its behavior assertion: ${mutation.name}\n${output}`);
    console.log(`PASS: tests reject ${mutation.name}`);
  }
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
