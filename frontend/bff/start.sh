#!/bin/sh
set -e

# Start Fastify server (serves both frontend static files and BFF API)
echo "Starting server..."
exec node /app/bff/server.js

