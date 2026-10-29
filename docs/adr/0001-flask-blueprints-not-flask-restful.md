# ADR 0001: Keep Flask blueprints instead of Flask-RESTful

- Status: accepted
- Date: 2026-10-29

## Context

The course catalog (Project 12) lists Flask-RESTful in the stack. The ReadAloud
backend was written with plain Flask blueprints (`auth`, `documents`, `tts`,
`analytics`), one module per resource, each route a small function with a
`@bp.get/post/put/delete` decorator.

Flask-RESTful's last release was in 2023 and it adds a `Resource` class per URL
plus its own `reqparse`, which is deprecated in favour of external validators.

## Decision

Keep blueprints. The API already behaves the way the catalog asks:

- Resource-oriented URLs: `/api/documents`, `/api/documents/<id>`,
  `/api/documents/<id>/ask`, `/api/documents/<id>/history`, `/api/analytics`.
- Correct HTTP verbs and status codes (201 on create, 204 on delete, 400/401/404/
  409/413/422/502 for errors).
- Every error, including 404/405 from Flask, token errors from
  Flask-JWT-Extended and unexpected 500s, is JSON `{"error": "..."}`
  (`app/__init__.py`).
- Flask-SQLAlchemy and Flask-Migrate are used as the catalog asks.

## Consequences

- No rewrite of working, tested routes two weeks before the demo.
- One way of writing routes in the codebase, which keeps it easy to explain in class.
- If Flask-RESTful is required later, each blueprint maps one-to-one onto a
  `Resource` class (the URL rules stay the same), so converting is mechanical.
