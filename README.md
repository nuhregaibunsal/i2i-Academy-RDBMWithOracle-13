# i2i Academy — RDBMS with Oracle

A production-style vertical slice that pushes data-processing logic **into the
database** (Oracle PL/SQL) and exposes it through a thin **Spring Boot** REST
facade. Raw delimited text is transformed to JSON inside Oracle, shredded
natively with `JSON_TABLE`, normalised into three tables, and read back through
an **explicit cursor**.

```
raw text ──POST──▶ Spring Boot ──JDBC──▶ BOOK_MGMT_PKG ──▶ AUTHORS / PUBLISHERS / BOOKS
   JSON  ◀──GET──── (REF CURSOR) ◀──────── explicit cursor ◀──────────────┘
```

## Tech stack
- Oracle Database XE 18c / 21c
- PL/SQL (packages, `JSON_TABLE`, explicit cursors, `RAISE_APPLICATION_ERROR`)
- Java 17 · Spring Boot 3.3 · Oracle JDBC (`ojdbc11`)

## Project layout
```
db/
  01_schema.sql        -- AUTHORS, PUBLISHERS, BOOKS + object types
  02_package_spec.sql  -- BOOK_MGMT_PKG public contract
  03_package_body.sql  -- transform / import / fetch implementation
  04_smoke_test.sql    -- manual SQL*Plus verification
backend/
  pom.xml
  src/main/java/com/i2i/academy/rdbms/...   -- controller, service, dto, exceptions
  src/main/resources/application.properties
requests.http          -- ready-to-run endpoint calls
```

## Setup
1. **Database** — connect to Oracle XE as the application user and run, in order:
   ```sql
   @db/01_schema.sql
   @db/02_package_spec.sql
   @db/03_package_body.sql
   @db/04_smoke_test.sql   -- optional
   ```
2. **Backend** — provide credentials via environment variables and start:
   ```bash
   export ORACLE_URL=jdbc:oracle:thin:@localhost:1521/XEPDB1
   export ORACLE_USER=i2i_app
   export ORACLE_PASSWORD=your_password
   cd backend && mvn spring-boot:run
   ```

## API
| Method | Path                | Body            | Success | Errors |
|--------|---------------------|-----------------|---------|--------|
| POST   | `/api/books/import` | `text/plain`    | 201     | 400 (ORA-200xx), 500 |
| GET    | `/api/books`        | —               | 200     | 500 |

**Raw import format** — records split by `~`, fields split by `|`:
```
title|isbn|pubYear|authorFirst|authorLast|authorBirth|publisherName|publisherCountry
```

See [`requests.http`](requests.http) for runnable examples.
