# Tables

- [user](user.md)
- [item](item.md)

One `User` has many `Item`s (`owner_id` foreign key, cascade delete). Schema managed by
Alembic migrations, not `SQLModel.metadata.create_all` — see `../SKILL.md` for how to
write one.
