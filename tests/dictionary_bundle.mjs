import assert from 'node:assert/strict'
import {createHash} from 'node:crypto'
import dictionaryPart1 from '../spellcheck/DictionaryPart1.mjs'
import dictionaryPart2 from '../spellcheck/DictionaryPart2.mjs'

// Pinned dictionary-en 4.0.0 index.dic, including all flags and final newline.
// This is independent of the generator and requires no npm install or network.
assert.equal(createHash('sha256').update(dictionaryPart1 + dictionaryPart2)
  .digest('hex'), 'f0b1a234bd178bdd01875b2a392a9647f888b8fe879f79c52aae62c2759b3647')
console.log('PASS: dictionary modules preserve every original dictionary byte')
