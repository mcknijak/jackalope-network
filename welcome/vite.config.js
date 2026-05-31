import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Single-page static landing built into dist/, served by Caddy.
export default defineConfig({
  plugins: [react()],
  build: {
    outDir: 'dist',
    sourcemap: false,
    emptyOutDir: true,
  },
});
