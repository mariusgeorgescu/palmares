// Valorile de build-time, citite din `import.meta.env` și înlocuite de Vite la bundle.
//
// Default-urile sunt căile BFF-ului și magic-ul preprod. Sunt sigure ca default-uri — spre deosebire
// de cele din `bff/config.js`, pe care le-am scos — pentru că niciuna nu e o credențială: un prefix
// greșit dă 404 pe loc, iar magic-ul greșit e prins de verificarea de rețea înainte de orice
// semnătură.
//
// `import.meta.env` se capturează într-o constantă, cu un obiect gol pe lipsă, pentru că modulul
// ăsta se importă și ÎN AFARA lui Vite: suita de teste rulează pe Node, unde `import.meta.env` e
// `undefined`, iar accesul direct arunca `TypeError` la import — adică întreaga suită cădea înainte
// să ruleze primul test, din cauza unui modul pe care niciun test nu-l exersează. Vite injectează
// `import.meta.env` ca obiect real, deci captura nu strică înlocuirea de la build.
const env = (typeof import.meta !== 'undefined' && import.meta.env) || {};

export const queryBaseUrlImpl = env.VITE_PALMARES_QUERY_BASE_URL || '/api/query';

export const interactionBaseUrlImpl =
  env.VITE_PALMARES_INTERACTION_BASE_URL || '/api/interaction';

// Trimis ca string și parsat în PureScript: `Number("abc")` dă NaN, care ar circula drept Int.
export const networkMagicImpl = String(env.VITE_PALMARES_NETWORK_MAGIC ?? '1');
