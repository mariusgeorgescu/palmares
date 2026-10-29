// Conectarea, dintr-un singur loc.
//
// Produsul are UN loc de conectare — widget-ul din bara de sus — și suita trebuie să treacă prin
// el, nu pe lângă. Înainte avea două: ecranul de scriere își conecta propriul wallet, iar cele două
// stări nu se vedeau între ele. Owner-ul a raportat exact asta: conectat sus, „Connect a wallet" pe
// „Actions". Un helper aici, pe lângă faptul că scurtează, ține suita pe calea omului: dacă mâine
// cineva mai adaugă un buton de conectare într-un ecran, niciun test de aici nu-l va folosi.
//
// Lista widget-ului numește extensiile cu CHEIA CIP-30 (`lace`), nu cu numele afișat de `getName`.

/** Deschide widget-ul din bara de sus și conectează extensia cu cheia dată. */
export async function connectFromNavbar(page, wallet) {
  await page.getByRole('button', { name: /Connect/ }).first().click();
  // `listitem`, nu text liber: linkurile din bară sunt și ele `li`, iar filtrul pe text ar fi
  // prins un element de meniu dacă vreodată un wallet s-ar numi ca o secțiune.
  await page.getByRole('listitem').filter({ hasText: wallet }).first().click();
}
