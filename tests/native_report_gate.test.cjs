const assert = require('node:assert/strict');
const {check} = require('./check_native_reports.cjs');
const names = ['1KiB', '10KiB', '25KiB', '100KiB'];
const log = (rows, summary = {workloadCount: 4, failures: []}) =>
  rows.map(row => 'PERF_NATIVE_RESULT: ' + JSON.stringify(row)).join('\n') +
  '\nPERF_NATIVE_SUMMARY: ' + JSON.stringify(summary);
const rows = names.map(name => ({name, failures: []}));
assert.equal(check('performance', log(rows)), 4);
assert.throws(() => check('performance', log(rows.map((row, i) =>
  i === 2 ? {...row, failures: ['broken']} : row))));
assert.throws(() => check('performance', log(rows.slice(1))));
assert.throws(() => check('performance', log([rows[0], rows[0], ...rows.slice(2)])));
assert.throws(() => check('performance', log(rows) + '\nPERF_NATIVE_SUMMARY: {}'));
const parity = 'NATIVE_PARITY_CASE: {"name":"required","failures":0}\n' +
  'NATIVE_PARITY_SUMMARY: {"expectedCaseCount":1,"ranCaseCount":1,"missingCases":[],"failures":[]}';
assert.equal(check('parity', parity, ['required']), 1);
assert.throws(() => check('parity', parity, ['required', 'deleted']));
assert.throws(() => check('parity', parity.replace('"failures":0', '"failures":1'), ['required']));
console.log('PASS: native report gate rejects mixed failures and missing or duplicate coverage');
