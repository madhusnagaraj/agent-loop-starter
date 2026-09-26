---
name: dev-validation
description: How a worker proves its own change in a real, fenced environment — provisioning (Docker or cloud dev), the seed-derived oracle, and Playwright UI + API checks. Load when validating a change, building the validation harness, or wiring the dev environment.
---

# Dev validation — proving a change in a real environment

Unit tests with mocks don't catch the failures that only appear when code runs against a **real database and a real UI**. A worker that vouches for its own change needs a disposable, seeded, fenced environment of its own — not production, not a working tree mid-edit.

## Provisioning (pick one)
- **Docker stack:** `docker compose up` brings up the app + a real database + dependencies, seeded with synthetic data. Spin up, test, tear down. Isolated, reproducible, free, can't touch anything real.
- **Cloud dev environment:** deploy the branch to an ephemeral environment and connect to it. Higher fidelity, but needs scoped, read-mostly credentials (the credential boundary earns its keep here).

## The verification loop
```
seed   the database with known synthetic data   # now you know the right answer
unit   run the tests you just wrote              # fast; first line of defense
ui     drive the changed pages with Playwright   # assert content, 0 console errors, exercise the CRUD
api    hit the endpoints directly (Playwright request / curl)  # status + payload isolates UI vs gateway vs backend
check  compare what rendered against the seed    # a grounded assertion, not a guess
keep   crystallize the passing run into a spec   # committed regression test
```

## Why the seed is the oracle
Because you seeded the data, you know what the screen and the endpoint *should* say — you check a known input against a known output instead of asking "does this look right?" Write the unit tests **first**, so "tests pass" means something before a browser ever opens.

## Fence it
The environment pokes a real stack, so it gets the same controls as everything else: **synthetic data only, outbound side effects off, credentials scoped to read.** Self-heal stays in the cage — fix and re-run on test files and the change only, never reaching for production or anything that emits a side effect. The fidelity that makes the environment useful is exactly what makes the fence non-optional.
