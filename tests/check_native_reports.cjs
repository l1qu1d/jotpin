const fs = require('node:fs');
const assert = require('node:assert/strict');
function records(log, marker) {
  return log.split('\n').filter(line => line.includes(marker + ': '))
    .map(line => JSON.parse(line.slice(line.indexOf(marker + ': ') + marker.length + 2)));
}
function check(mode, log, expectedNames) {
  const parity = mode === 'parity';
  const prefix = parity ? 'NATIVE_PARITY' : 'PERF_NATIVE';
  const rows = records(log, prefix + (parity ? '_CASE' : '_RESULT'));
  const summaries = records(log, prefix + '_SUMMARY');
  assert.equal(summaries.length, 1, 'expected one summary');
  const summary = summaries[0];
  assert.deepEqual(summary.failures, [], 'summary contains failures');
  const expected = parity ? expectedNames : ['1KiB', '10KiB', '25KiB', '100KiB'];
  assert.deepEqual(rows.map(row => row.name).sort(), expected.slice().sort(),
    'missing, duplicate or unregistered workload');
  for (const row of rows)
    assert.deepEqual(row.failures, parity ? 0 : [], `failed workload ${row.name}`);
  if (parity) {
    assert.equal(summary.expectedCaseCount, expected.length);
    assert.equal(summary.ranCaseCount, expected.length);
    assert.deepEqual(summary.missingCases, []);
  } else assert.equal(summary.workloadCount, expected.length);
  return rows.length;
}
module.exports = {check};
if (require.main === module) {
  try {
    const mode = process.argv[2];
    assert(['parity', 'performance'].includes(mode));
    const expected = mode === 'parity' ? require('./native_parity_contracts.json') : null;
    const count = check(mode, fs.readFileSync(process.argv[3], 'utf8'), expected);
    console.log(`PASS: every ${mode} record validated (${count} required cases)`);
  } catch (error) {
    console.error(`FAIL: native report validation: ${error.message}`);
    process.exitCode = 1;
  }
}
