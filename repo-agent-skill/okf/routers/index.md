# Routers

All mounted under `/api/v1` (`API_V1_STR` in `app/core/config.py`), combined in
`backend/app/api/main.py`.

- [login](login.md) — `/login/*`, `/password-recovery*`, `/reset-password/`
- [users](users.md) — `/users/*`
- [items](items.md) — `/items/*`
- [utils](utils.md) — `/utils/*`
- [private](private.md) — `/private/*` (dev-only)

Full request/response schemas: `../../docs/api/openapi.json`.
