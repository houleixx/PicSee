(() => {
  'use strict';

  const storageKey = 'picsee-language';
  const isLanguage = (value) => value === 'zh-CN' || value === 'en';
  const url = new URL(window.location.href);
  // An explicit URL choice also lets switching work when storage is blocked.
  const explicitLanguage = url.searchParams.get('lang');
  let savedLanguage;
  try {
    savedLanguage = window.localStorage.getItem(storageKey);
  } catch {
    // Browser privacy settings may make localStorage unavailable.
  }

  document.addEventListener('click', (event) => {
    const link = event.target.closest('.language-switch a[hreflang]');
    if (!link || event.defaultPrevented) return;
    const language = link.hreflang;
    if (!isLanguage(language)) return;

    try {
      window.localStorage.setItem(storageKey, language);
      if (window.localStorage.getItem(storageKey) === language) return;
    } catch {
      // Keep the ordinary link usable even if saving the preference fails.
    }
    const destination = new URL(link.href);
    destination.searchParams.set('lang', language);
    link.href = destination.href;
  });

  // Shared English URLs remain English, regardless of browser or saved language.
  if (url.pathname !== '/' && url.pathname !== '/index.html') return;

  const browserLanguage = navigator.languages?.[0] || navigator.language || 'zh-CN';
  const language = isLanguage(explicitLanguage) ? explicitLanguage
    : isLanguage(savedLanguage) ? savedLanguage
    : /^zh(?:-|$)/i.test(browserLanguage) ? 'zh-CN' : 'en';

  if (language === 'en') {
    url.pathname = '/en/';
    window.location.replace(url.href);
  }
})();
