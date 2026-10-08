const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const website = path.resolve(__dirname, '../../website');
const scriptPath = fs.readFileSync(path.join(website, 'index.html'), 'utf8')
  .match(/<script src="(assets\/language-[a-f0-9]+\.js)"><\/script>/)[1];
const script = fs.readFileSync(path.join(website, scriptPath), 'utf8');

function visit({ url = 'https://picsee.pages.dev/', languages = ['en-US'], saved, blocked = false } = {}) {
  let redirect;
  let onClick;
  const storage = new Map(saved === undefined ? [] : [['picsee-language', saved]]);
  const localStorage = {
    getItem(key) { if (blocked) throw Error('Storage blocked'); return storage.get(key) ?? null; },
    setItem(key, value) { if (blocked) throw Error('Storage blocked'); storage.set(key, value); },
  };
  vm.runInNewContext(script, {
    URL,
    window: { localStorage, location: { href: url, replace(value) { redirect = value; } } },
    navigator: { languages, language: languages[0] },
    document: { addEventListener(type, callback) { assert.equal(type, 'click'); onClick = callback; } },
  });
  return {
    redirect, storage,
    click(language) {
      const link = { hreflang: language, href: `https://picsee.pages.dev/${language === 'en' ? 'en/' : ''}` };
      onClick({ target: { closest: () => link }, defaultPrevented: false });
      return link.href;
    },
  };
}

test('first visit follows the primary browser language, including Chinese variants', () => {
  for (const language of ['zh', 'zh-CN', 'zh-TW', 'zh-Hant', 'ZH-hk'])
    assert.equal(visit({ languages: [language] }).redirect, undefined);
  for (const language of ['en-US', 'ja-JP', 'de-DE'])
    assert.equal(visit({ languages: [language, 'zh-CN'] }).redirect, 'https://picsee.pages.dev/en/');
  assert.equal(visit({ languages: [] }).redirect, undefined);
});
test('saved manual choice takes priority; invalid saved values are ignored', () => {
  assert.equal(visit({ saved: 'zh-CN' }).redirect, undefined);
  assert.equal(visit({ saved: 'en', languages: ['zh-CN'] }).redirect, 'https://picsee.pages.dev/en/');
  assert.equal(visit({ saved: 'invalid' }).redirect, 'https://picsee.pages.dev/en/');
});
test('direct English URLs remain English and do not overwrite preferences', () => {
  for (const pathname of ['/en/', '/en/index.html']) {
    const page = visit({ url: `https://picsee.pages.dev${pathname}`, saved: 'zh-CN' });
    assert.equal(page.redirect, undefined);
    assert.equal(page.storage.get('picsee-language'), 'zh-CN');
  }
});
test('automatic redirects preserve query and fragment, without persisting inferred preferences', () => {
  const page = visit({ url: 'https://picsee.pages.dev/index.html?source=share#formats-title' });
  assert.equal(page.redirect, 'https://picsee.pages.dev/en/?source=share#formats-title');
  assert.equal(page.storage.size, 0);
});
test('manual choices persist and allow returning to Chinese in an English browser', () => {
  const page = visit({ url: 'https://picsee.pages.dev/en/' });
  assert.equal(page.click('zh-CN'), 'https://picsee.pages.dev/');
  assert.equal(visit({ saved: page.storage.get('picsee-language') }).redirect, undefined);
  page.click('en');
  assert.equal(page.storage.get('picsee-language'), 'en');
});
test('blocked storage does not break automatic detection or manual switching', () => {
  assert.equal(visit({ blocked: true }).redirect, 'https://picsee.pages.dev/en/');
  const page = visit({ url: 'https://picsee.pages.dev/en/', blocked: true });
  const url = page.click('zh-CN');
  assert.equal(url, 'https://picsee.pages.dev/?lang=zh-CN');
  assert.equal(visit({ url, blocked: true }).redirect, undefined);
});
test('both pages load the same content-hashed script', () => {
  assert.ok(fs.readFileSync(path.join(website, 'en/index.html'), 'utf8').includes(`src="../${scriptPath}"`));
  const hash = require('node:crypto').createHash('sha256').update(script).digest('hex').slice(0, 8);
  assert.ok(scriptPath.includes(hash));
});
