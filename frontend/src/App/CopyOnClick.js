// Un singur listener delegat pe `document`, exact forma lui `SpaLinkInterceptor`.
//
// De ce aşa şi nu `HE.onClick` în componentă: butonul de copiere apare în vreo zece locuri, iar un
// handler Halogen ar cere un constructor de Action în fiecare componentă gazdă plus o clasă de
// capabilitate pentru clipboard. Cu un listener delegat, chipul rămâne `forall w i` — HTML pur,
// fără monadă, fără stare — şi poate fi folosit din orice randare, inclusiv din funcţii care nu
// sunt componente.
export const installCopyOnClickImpl = () => {
  document.addEventListener('click', function (event) {
    var el = event.target.closest('[data-copy]');
    if (!el) return;

    var value = el.getAttribute('data-copy');
    if (!value) return;

    event.preventDefault();
    event.stopPropagation();

    // `navigator.clipboard` lipseşte pe origini nesecure şi în unele browsere vechi. Fallback-ul pe
    // `execCommand` e depreciat dar funcţionează; dacă nici el nu merge, nu se marchează nimic —
    // un „Copied!" fals e mai rău decât niciun feedback.
    var done = function () {
      el.classList.add('copied');
      window.setTimeout(function () {
        el.classList.remove('copied');
      }, 1200);
    };

    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(value).then(done, function () {});
        return;
      }
    } catch (e) {
      // cade pe varianta de mai jos
    }

    try {
      var ta = document.createElement('textarea');
      ta.value = value;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      var ok = document.execCommand('copy');
      document.body.removeChild(ta);
      if (ok) done();
    } catch (e) {
      // fără feedback, deliberat
    }
  });
};
