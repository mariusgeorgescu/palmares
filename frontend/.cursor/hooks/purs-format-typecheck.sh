#!/usr/bin/env bash
set -e

# Read JSON from stdin (Cursor sends hook payload here)
input=$(cat)

# Extract file_path (works with sed; use jq -r '.file_path // empty' if jq available)
file_path=$(echo "$input" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

# Only run for PureScript files
case "$file_path" in
  *.purs)
    # Format the edited file in place
    npx purs-tidy format-in-place "$file_path"
    # Typecheck the project
    npx spago build --json-errors
    ;;
  *)
    ;;
esac

exit 0
