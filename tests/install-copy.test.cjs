// Offline DOM/clipboard mocks, not a substitute for browser integration tests.
// Run: node --test tests/install-copy.test.cjs
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const script = fs.readFileSync(path.join(root, 'install-copy.js'), 'utf8');

class Element {
  constructor(tag, text = '') { this.tag = tag; this.textContent = text; this.children = []; this.className = ''; this.events = {}; this.style = {}; this.attributes = {}; this.disabled = false; }
  get classList() { return { contains: name => this.className.split(/\s+/).includes(name) }; }
  appendChild(child) { child.remove(); this.children.push(child); child.parentElement = this; return child; }
  remove() { if (this.parentElement) { const p = this.parentElement; p.children.splice(p.children.indexOf(this), 1); this.parentElement = null; } }
  before(child) { const p = this.parentElement; p.children.splice(p.children.indexOf(this), 0, child); child.parentElement = p; }
  closest(tag) { for (let e = this; e; e = e.parentElement) if (e.tag === tag) return e; return null; }
  querySelectorAll(selector) {
    assert.equal(selector, 'pre > code');
    const result = [];
    function visit(e) { for (const child of e.children) { if (e.tag === 'pre' && child.tag === 'code') result.push(child); visit(child); } }
    visit(this); return result;
  }
  setAttribute(key, value) { this.attributes[key] = value; }
  addEventListener(type, fn) { this.events[type] = fn; }
  focus() {} select() {}
}

function fixture(file, mode = 'success') {
  const html = fs.readFileSync(path.join(root, file), 'utf8');
  assert.ok(!html.includes('</script>>'), 'no stray > after script');
  const lang = /<html[^>]*lang="([^"]+)"/.exec(html)[1];
  const sectionHTML = /<section>\s*<h2 id="section-1">([\s\S]*?)<\/section>/.exec(html)[1];
  const body = new Element('body'), section = new Element('section'), heading = new Element('h2');
  body.appendChild(section); section.appendChild(heading);
  const decode = text => text.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'");
  // Model real command blocks from each HTML file; heading and pre are siblings.
  for (const m of sectionHTML.matchAll(/<pre><code>([\s\S]*?)<\/code><\/pre>/g)) {
    const pre = new Element('pre'); section.appendChild(pre); pre.appendChild(new Element('code', decode(m[1])));
  }
  const inlineCount = [...sectionHTML.matchAll(/<code>/g)].length - section.querySelectorAll('pre > code').length;
  const paragraph = new Element('p'); section.appendChild(paragraph);
  for (let i = 0; i < inlineCount; i++) paragraph.appendChild(new Element('code', 'inline'));
  const outside = new Element('pre'); body.appendChild(outside); outside.appendChild(new Element('code', 'outside section'));
  const writes = [], timers = []; let fallbacks = 0, selected = null;
  const document = {
    documentElement: { lang }, readyState: 'complete', body,
    getElementById: id => id === 'section-1' ? heading : null,
    querySelectorAll: selector => { assert.equal(selector, '#section-1 pre > code'); return heading.querySelectorAll('pre > code'); },
    createElement: tag => new Element(tag),
    execCommand: command => { assert.equal(command, 'copy'); fallbacks++; return mode !== 'failure'; },
    createRange: () => ({ selectNodeContents: node => { selected = node; } }),
  };
  const navigator = mode === 'legacy' ? {} : { clipboard: { writeText: async text => { if (mode !== 'success') throw Error('clipboard unavailable'); writes.push(text); } } };
  const window = { setTimeout: fn => { timers.push(fn); }, getSelection: () => ({ removeAllRanges() {}, addRange() {} }) };
  const context = vm.createContext({ document, navigator, window });
  const run = () => vm.runInContext(script, context);
  run();
  const buttons = () => section.children.flatMap(e => e.children).filter(e => e.className === 'manual-command-copy');
  return { buttons, section, paragraph, outside, writes, timers, run, lang, get fallbacks() { return fallbacks; }, get selected() { return selected; }, document };
}

for (const file of ['Manual_EN.html', 'jp/manual.html']) {
  test(`${file}: seven scoped, localized buttons; idempotent and clipboard success`, async () => {
    const f = fixture(file);
    assert.equal(f.buttons().length, 7);
    assert.ok(f.paragraph.children.every(e => e.tag === 'code'));
    assert.equal(f.outside.parentElement.tag, 'body');
    f.run(); assert.equal(f.buttons().length, 7);
    const button = f.buttons()[0];
    assert.equal(button.textContent, f.lang.startsWith('ja') ? 'コピー' : 'Copy');
    const expected = button.parentElement.children[0].children[0].textContent.trim();
    await button.events.click();
    assert.deepEqual(f.writes, [expected]); assert.equal(f.fallbacks, 0);
    assert.equal(button.disabled, true);
    await button.events.click(); assert.equal(f.writes.length, 1);
    assert.equal(button.textContent, f.lang.startsWith('ja') ? 'コピーしました' : 'Copied');
    f.timers.shift()(); assert.equal(button.disabled, false);
  });
  for (const mode of ['fallback', 'legacy', 'failure']) test(`${file}: ${mode}`, async () => {
    const f = fixture(file, mode); const button = f.buttons()[0];
    assert.ok(button); await button.events.click(); assert.equal(f.fallbacks, 1);
    assert.equal(f.document.body.children.filter(e => e.tag === 'textarea').length, 0);
    assert.equal(button.textContent, mode === 'failure' ? (f.lang.startsWith('ja') ? 'コピーできませんでした' : 'Copy failed') : (f.lang.startsWith('ja') ? 'コピーしました' : 'Copied'));
    assert.equal(Boolean(f.selected), mode === 'failure');
    f.timers.shift()(); assert.equal(button.disabled, false);
  });
}
test('missing section is harmless', () => {
  const f = fixture('Manual_EN.html'); f.document.getElementById = () => null; assert.doesNotThrow(f.run);
});
