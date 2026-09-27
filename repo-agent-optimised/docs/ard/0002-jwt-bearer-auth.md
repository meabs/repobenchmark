# 0002. JWT bearer tokens for auth, Argon2/bcrypt for password storage

## Status
Accepted (`backend/app/core/security.py`, `backend/app/api/deps.py`)

## Context
The API needs stateless auth (no server-side session store) that works for both the
SPA frontend and direct API clients, plus safe password storage that can be upgraded
over time without forcing a mass password reset.

## Decision
- **Tokens**: `POST /api/v1/login/access-token` (OAuth2 password flow, via
  `OAuth2PasswordRequestForm`) issues a JWT signed with `settings.SECRET_KEY`, algorithm
  `HS256`, containing `sub` (the user's UUID) and `exp`
  (`ACCESS_TOKEN_EXPIRE_MINUTES`, default 8 days). Every protected route depends on
  `CurrentUser` (`app/api/deps.py`), which decodes and validates this token via
  `OAuth2PasswordBearer(tokenUrl=".../login/access-token")`.
- **Password hashing**: `pwdlib.PasswordHash` configured with `Argon2Hasher()` first,
  `BcryptHasher()` second (`app/core/security.py`). Argon2 is used for all new hashes;
  bcrypt is kept only so existing bcrypt hashes still verify.
  `verify_password` returns `(verified, updated_hash)` — `pwdlib` transparently
  re-hashes a successfully-verified legacy bcrypt password to Argon2, and callers
  (`crud.authenticate`) persist that upgraded hash. This means password hashes migrate
  to Argon2 automatically, one successful login at a time, with no batch migration
  needed.
- **Timing-attack mitigation**: `crud.authenticate` runs `verify_password` against a
  fixed `DUMMY_HASH` even when the email isn't found, so a login attempt against a
  nonexistent account takes about as long as one against a real account with a wrong
  password — this prevents using response time to enumerate valid emails.

## Consequences
- No server-side session/logout mechanism exists — a token is valid until it expires.
  Revoking access before expiry (e.g. on password change) would need a separate
  mechanism (denylist, token version field, etc.) — there isn't one currently.
- `SECRET_KEY` is a single symmetric key; rotating it invalidates every outstanding
  token.
