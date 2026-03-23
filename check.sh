#!/bin/bash
 
# Run Commands:
# bash check.sh                  # run lint + prettier check
# bash check.sh --fix            # run lint + prettier auto-fix
# bash check.sh --no-lint        # prettier only
# bash check.sh --no-prettier    # lint only
# bash check.sh --no-lint --fix  # prettier auto-fix only

# --- Feature toggles ---
RUN_LINT=true
RUN_PRETTIER=true
PRETTIER_FIX=false  # false = check only, true = auto-fix

# --- Argument parsing ---
for arg in "$@"; do
  case $arg in
    --no-lint)       RUN_LINT=false ;;
    --no-prettier)   RUN_PRETTIER=false ;;
    --fix)           PRETTIER_FIX=true ;;
  esac
done

# --- Run ---
FAILED=false

if $RUN_LINT; then
  echo "Running ESLint..."
  npm run lint
  [ $? -ne 0 ] && FAILED=true
fi

if $RUN_PRETTIER; then
  if $PRETTIER_FIX; then
    echo "Running Prettier (fix)..."
    npm run prettier
  else
    echo "Running Prettier (check)..."
    npm run prettier:check
  fi
  [ $? -ne 0 ] && FAILED=true
fi

if $FAILED; then
  echo "One or more checks failed."
  exit 1
else
  echo "All checks passed."
fi