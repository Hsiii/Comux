import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

const config = defineConfig({
    plugins: [react()],
    server: {
        open: true,
    },
});

export default config;
