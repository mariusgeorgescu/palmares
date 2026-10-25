import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineConfig } from 'vite';
import wasm from 'vite-plugin-wasm';
import topLevelAwait from 'vite-plugin-top-level-await';
import tailwindcss from '@tailwindcss/vite';
import { nodePolyfills } from 'vite-plugin-node-polyfills';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// libsodium-wrappers-sumo's ESM build does `import "./libsodium-sumo.mjs"`,
// but that file lives in the separate `libsodium-sumo` package. Patch both
// phases so Cardano serialization (used by CIP-30 wallets) bundles cleanly:
//   1) esbuild pre-bundling via optimizeDeps plugin
//   2) Vite dev-serve via a Vite resolveId plugin
const libsodiumSumoPath = path.resolve(
  __dirname,
  'node_modules/libsodium-sumo/dist/modules-sumo-esm/libsodium-sumo.mjs'
);

function fixLibsodiumImport() {
  return {
    name: 'fix-libsodium-sumo-import',
    resolveId(source, importer) {
      if (source === './libsodium-sumo.mjs' && importer?.includes('libsodium-wrappers-sumo')) {
        return libsodiumSumoPath;
      }
    },
  };
}

// The pinned halogen-cardano-wallet-connect-component dynamically imports
// @utxos/sdk and @meshsdk/core. The template ships in CIP-30-only mode and
// never executes those code paths (renderMode: Standalone, utxosConfig:
// Nothing), so stub the imports out so we don't have to install ~50 MB of
// optional deps. If you opt into UTXOS later, `npm install @utxos/sdk
// @meshsdk/core` and remove this plugin (and the `external` entries below).
const STUB_PACKAGES = new Set(['@utxos/sdk', '@meshsdk/core']);
function stubOptionalWalletSdks() {
  const virtualId = '\0template-empty-stub';
  return {
    name: 'stub-optional-wallet-sdks',
    resolveId(source) {
      if (STUB_PACKAGES.has(source)) return virtualId;
    },
    load(id) {
      if (id === virtualId) return 'export default {};';
    },
  };
}

export default defineConfig({
  optimizeDeps: {
    esbuildOptions: {
      plugins: [
        {
          name: 'fix-libsodium-sumo-esbuild',
          setup(build) {
            build.onResolve({ filter: /^\.\/libsodium-sumo\.mjs$/ }, (args) => {
              if (args.importer.includes('libsodium-wrappers-sumo')) {
                return { path: libsodiumSumoPath };
              }
            });
          },
        },
      ],
    },
  },
  plugins: [
    fixLibsodiumImport(),
    stubOptionalWalletSdks(),
    nodePolyfills({
      include: ['buffer', 'process', 'events', 'util', 'stream', 'crypto'],
      globals: { Buffer: true, process: true },
    }),
    wasm(),
    topLevelAwait(),
    tailwindcss(),
  ],
  // Vite dev-server proxy. ONLY used by `vite dev` — production traffic goes
  // through the Fastify BFF, which has its own proxy config in bff/config.js.
  // Keep the routes here in sync with the BFF's `services` keys.
  server: {
    proxy: {
      '/api/api': {
        target: 'http://0.0.0.0:8083',
        rewrite: (p) => p.replace(/^\/api\/api/, ''),
        changeOrigin: true,
        auth: 'cardano:lovelace',
      },
      // Example: streaming (SSE) backend — disable timeouts so chunks reach the browser.
      // '/api/chatbot': {
      //   target: 'http://0.0.0.0:8090',
      //   rewrite: (p) => p.replace(/^\/api\/chatbot/, ''),
      //   changeOrigin: true,
      //   ws: false,
      //   timeout: 0,
      //   proxyTimeout: 0,
      // },
    },
  },
});
