# Tables

- [user](user.md)
- [item](item.md)

One `User` has many `Item`s (`owner_id` foreign key, cascade delete). Schema managed by
[Alembic migrations](../../docs/ard/0004-alembic-migrations.md), not
`SQLModel.metadata.create_all`.
