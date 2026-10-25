// Valorile de build-time, citite din `import.meta.env` și înlocuite de Vite la bundle.
//
// Default-urile sunt căile BFF-ului și magic-ul preprod. Sunt sigure ca default-uri — spre deosebire
// de cele din `bff/config.js`, pe care le-am scos — pentru că niciuna nu e o credențială: un prefix
// greșit dă 404 pe loc, iar magic-ul greșit e prins de verificarea de rețea înainte de orice
// semnătură.

export const queryBaseUrlImpl =
  import.meta.env.VITE_PALMARES_QUERY_BASE_URL || '/api/query';

export const interactionBaseUrlImpl =
  import.meta.env.VITE_PALMARES_INTERACTION_BASE_URL || '/api/interaction';

// Trimis ca string și parsat în PureScript: `Number("abc")` dă NaN, care ar circula drept Int.
export const networkMagicImpl =
  String(import.meta.env.VITE_PALMARES_NETWORK_MAGIC ?? '1');
