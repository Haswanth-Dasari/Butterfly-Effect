All SQL lives here. Files are numbered to run in order.

## Local database setup

1. Install PostgreSQL 16+ and ensure `psql` is on `PATH`.
2. Create the database: `psql -U postgres -c "CREATE DATABASE butterfly;"`
3. Apply extensions: `psql -U postgres -d butterfly -f db/schema/00_extensions.sql`
4. Copy `.env.example` to `.env` and fill in your password.
