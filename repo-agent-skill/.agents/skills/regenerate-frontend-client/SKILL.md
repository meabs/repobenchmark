---
name: regenerate-frontend-client
description: Regenerate the frontend's generated TypeScript API client after a backend route or schema change in this repo — the script to run, and the manual fallback if bun isn't available.
---

# Regenerate the frontend client after a backend route/schema change

The frontend never hand-writes its API client — it's generated from the backend's
own OpenAPI schema.

```
bash scripts/generate-client.sh
```

This script assumes `bun` is on `PATH`. If it isn't, do the two steps it performs
manually instead:

```
cd backend
FASTAPI_ENV=development uv run python -c "import app.main; import json; print(json.dumps(app.main.app.openapi()))" > ../frontend/openapi.json
cd ../frontend
npx --yes @hey-api/openapi-ts   # or: npm install --no-save @hey-api/openapi-ts && npx openapi-ts
```

Never hand-edit anything under `frontend/src/client/` — the next regeneration
silently overwrites it.
