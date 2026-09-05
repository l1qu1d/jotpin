const assert = require('node:assert/strict');
const {check} = require('./check_qt_contracts.cjs');
const contracts = {Example: ['test_required()']};
const pass = name => `PASS   : qmltestrunner::Example::${name}\n`;
const good = pass('initTestCase()') + pass('test_required()') +
  pass('cleanupTestCase()') + 'Totals: 3 passed, 0 failed, 0 skipped, 0 blacklisted';
assert.equal(check(good, contracts), 1);
for (const bad of [
  '',
  good.replace(pass('test_required()'), '').replace('3 passed', '2 passed'),
  good.replace('0 skipped', '1 skipped'),
  good.replace('test_required()', 'test_renamed()'),
  good.replace('0 failed', '1 failed'),
  good + '\n' + pass('test_required()'),
  good + '\n' + good,
  good.replace('3 passed', '4 passed') + '\n' + pass('test_unregistered()'),
  good + '\nXFAIL : expected failure'
]) assert.throws(() => check(bad, contracts));
console.log('PASS: Qt result gate rejects missing, renamed, duplicated, skipped, failed and incomplete tests');
