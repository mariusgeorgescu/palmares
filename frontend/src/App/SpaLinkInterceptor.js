// Un slash final nu e o adresă diferită, deci nu are voie să fie o rută diferită.
//
// Normalizarea se face AICI, înaintea pornirii aplicației, pentru că `mkRouter routeCodec`
// (AppBase.purs) parsează cu CODECUL direct — `parseRoute` nu e pe drumul de rulare, e folosit
// numai de teste. Prima variantă a reparației a pus normalizarea în `parseRoute`, testul unitar a
// trecut, și `/profiles/` continua să dea „Not found" în browser: aceeași clasă cu filtrul care
// ajungea în URL și nu în cerere. Aici e singurul loc prin care trec TOATE intrările.
export const normaliseTrailingSlashImpl = () => {
  var path = window.location.pathname;
  if (path.length > 1 && path.endsWith('/')) {
    var stripped = path.slice(0, -1) + window.location.search + window.location.hash;
    window.history.replaceState(window.history.state, '', stripped);
  }
};

export const installSpaLinkInterceptorImpl = () => {
  document.addEventListener('click', function(event) {
    if (event.defaultPrevented) return;

    var anchor = event.target.closest('a');
    if (!anchor) return;

    var href = anchor.getAttribute('href');
    if (!href || !href.startsWith('/')) return;
    if (anchor.target && anchor.target !== '_self') return;
    if (event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;

    event.preventDefault();
    window.history.pushState({}, '', href);
    window.dispatchEvent(new PopStateEvent('popstate'));
  });
};
