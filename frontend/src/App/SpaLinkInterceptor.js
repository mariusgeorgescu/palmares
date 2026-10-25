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
