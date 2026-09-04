const fs = require('node:fs');

function check(log, contracts) {
  if (/FAIL!|QFATAL|SKIP\s*:|XFAIL|XPASS/.test(log))
    throw new Error('QtTest failed, skipped, or expected a failure');
  const totals = [...log.matchAll(/Totals: (\d+) passed, (\d+) failed, (\d+) skipped, (\d+) blacklisted/g)];
  if (totals.length !== 1 || totals[0].slice(2).some(n => Number(n) !== 0))
    throw new Error('expected one complete clean QtTest summary');
  const passes = [...log.matchAll(/^PASS\s*:\s+qmltestrunner::(.+)$/gm)].map(m => m[1].trim());
  if (Number(totals[0][1]) !== passes.length)
    throw new Error('QtTest summary and individual results disagree');
  let count = 0;
  const expected = [];
  for (const [suite, cases] of Object.entries(contracts)) {
    for (const name of ['initTestCase()', ...cases, 'cleanupTestCase()']) {
      const key = `${suite}::${name}`;
      expected.push(key);
      if (passes.filter(p => p === key).length !== 1)
        throw new Error(`required test did not pass exactly once: ${key}`);
    }
    count += cases.length;
  }
  if (passes.some(p => !expected.includes(p)))
    throw new Error('unregistered QtTest result; update the contract inventory');
  return count;
}

module.exports = {check};
if (require.main === module) {
  try {
    const count = check(fs.readFileSync(process.argv[2], 'utf8'),
      JSON.parse(fs.readFileSync(process.argv[3], 'utf8')));
    console.log(`PASS: all ${count} required pointer contracts executed without skips`);
  } catch (error) {
    console.error(`FAIL: ${error.message}`);
    process.exitCode = 1;
  }
}
