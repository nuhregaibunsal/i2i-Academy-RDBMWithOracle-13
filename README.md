# i2i Academy — RDBMS with Oracle

A production-style vertical slice that pushes data-processing logic **into the
database** (Oracle PL/SQL) and exposes it through a thin **Spring Boot** REST
facade. Raw delimited text is transformed into **both XML and JSON** inside
Oracle, parsed natively with `XMLTABLE` and `JSON_TABLE`, normalised into three
related tables, audited by a row-level trigger, and read back through an
**explicit cursor**. The whole stack runs with a single `docker compose up`, and
the schema/PL/SQL is provisioned automatically on startup by **Flyway**.

```
raw text ─POST─▶ Spring Boot ─fn_to_xml + fn_to_json─▶ XML + JSON
                      │                                     │
                      └──────── prc_import_books(xml, json) ┘
                                        │
                     XMLTABLE + JSON_TABLE → AUTHORS / PUBLISHERS / BOOKS
                                        │
                              trg_books_audit → AUDIT_LOGS
raw ◀─GET─ (REF CURSOR) ◀── prc_fetch_books (explicit cursor) ◀──┘
```

## Tech stack
- Oracle Database XE 21c (`gvenzl/oracle-xe`)
- PL/SQL — package `BOOK_OPERATIONS`, `XMLTABLE`, `JSON_TABLE`, explicit cursors,
  row-level trigger, `RAISE_APPLICATION_ERROR`
- Java 17 · Spring Boot 3.3 · Oracle JDBC (`ojdbc11`)
- Flyway (schema + PL/SQL migrations) · Docker Compose

## Project layout
```
docker-compose.yml                         Oracle XE + backend on one network
backend/
  Dockerfile
  pom.xml
  src/main/resources/
    application.properties
    db/migration/
      V1__schema.sql                        AUTHORS, PUBLISHERS, BOOKS, AUDIT_LOGS + types
      V2__audit_trigger.sql                 row-level INSERT trigger on BOOKS
      V3__book_operations_package.sql        BOOK_OPERATIONS package (spec + body)
  src/main/java/com/i2i/academy/rdbms/...    controller, service, dto, exceptions
requests.http                              ready-to-run endpoint calls
```

## Run everything with Docker
```bash
docker compose up --build
```
On startup the backend waits for Oracle to become healthy, then Flyway applies
`V1 → V2 → V3`, creating the schema, the audit trigger and the `BOOK_OPERATIONS`
package. The API is then available at `http://localhost:8080`.

## Connect with DBeaver
| Setting  | Value              |
|----------|--------------------|
| Host     | `localhost`        |
| Port     | `1521`             |
| Service  | `XEPDB1`           |
| User     | `i2i_app`          |
| Password | `i2i_pass`         |

## API
| Method | Path                | Body         | Success | Errors |
|--------|---------------------|--------------|---------|--------|
| POST   | `/api/books/import` | `text/plain` | 201     | 400 (ORA-200xx), 500 |
| GET    | `/api/books`        | —            | 200     | 500 |

**Raw import format** — records split by `~`, fields split by `|`:
```
title|author|publisher
```
Example:
```
Clean Code|Robert Martin|Prentice Hall~Refactoring|Martin Fowler|Addison-Wesley
```

See [`requests.http`](requests.http) for runnable examples.
