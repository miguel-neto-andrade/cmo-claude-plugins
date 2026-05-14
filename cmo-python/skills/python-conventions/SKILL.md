---
name: python-conventions
description: Use when writing, reviewing, refactoring, or scaffolding Python code (>= 3.10) in C-Mo repos. Captures naming rules, type-hint requirements, docstring style, error handling, logging, testing layout, the lint/format toolchain, and the project-specific PEP-8 rule exceptions.
---

# Python Conventions

Conventions for Python ≥ 3.10 in C-Mo repositories. Built on PEP 8 with the modernizations and project-specific rule exceptions listed below.

## Naming

- `snake_case` — variables, functions, methods, modules
- `CamelCase` — classes
- `UPPER_SNAKE_CASE` — module-level constants
- Functions use verb phrases (`calculate_total`, `fetch_user`, `is_valid`). Use complementary pairs: `get`/`set`, `add`/`remove`, `start`/`stop`.
- **No negated booleans** — `is_found` not `is_not_found`.
- **No abbreviations**, except idiomatic loop indices (`i`, `j`) and well-known domain shorthand (`df` for `pandas.DataFrame`, `ax` for matplotlib axes).
- **No shadowing** of Python builtins or stdlib (`list`, `dict`, `type`, `id`, `input`, …).
- One variable per statement, but tuple unpacking is fine: `a, b = some_func()`.
- English everywhere — names, comments, docstrings, log messages.

## Type hints (required)

**Type hints are required on every function, method, and public class attribute.** Untyped code is not acceptable in new contributions — review will reject it.

- Use modern PEP 604 / PEP 585 syntax: `list[int]` not `List[int]`, `str | None` not `Optional[str]`.
- `# type: ignore` requires a one-line justification: `# type: ignore[<rule>] — <why>`.
- `Any` is usually a smell — prefer a `Protocol`, `TypedDict`, or generic. Exception: dynamic data before it's been parsed (e.g., the immediate return of `json.loads`) — type it `Any` and narrow at the boundary (see **Boundary types** below).

```python
def calculate_total_price(item_price: float, quantity: int) -> float:
    """Return the total price for a given quantity of items.

    :param item_price: Price of a single item.
    :param quantity:   How many items.
    :return:           item_price * quantity.
    """
    return item_price * quantity
```

### mypy / pyright strict — pin the exact flags

"Strict" isn't a fixed target across versions; pin the minimum set in the project's config:

- `disallow_untyped_defs`
- `disallow_incomplete_defs`
- `disallow_any_explicit`
- `disallow_untyped_decorators`
- `warn_return_any`
- `warn_unused_ignores`
- `no_implicit_optional`
- `strict_equality`

Run as part of `make lint`; CI must fail on type errors.

### Useful type-system features (use when they fit)

- `Final` for module-level constants — `MAX_RETRIES: Final = 3`
- `Literal["draft", "published", "archived"]` for enum-like string params
- `@overload` for functions with multiple call signatures
- `TypeGuard[X]` for runtime narrowing in validators
- `Self` (Python 3.11+) for fluent / return-self methods
- PEP 695 syntax (Python 3.12+) — `def f[T](x: T) -> T:` and `type Vec = list[float]`

## Boundary types

At any system boundary, parse incoming data into a typed value object **before** passing it deeper into the code. Boundaries include:

- HTTP request bodies and query params
- JSON / YAML / CSV file parsing
- External API responses
- Message queue / event payloads
- Subprocess output being interpreted as structured data

**Use:**

- `pydantic.BaseModel` when you need validation, coercion, or serialization
- `@dataclass(frozen=True, slots=True)` for internal value objects after the boundary

**Don't:**

- Pass raw `dict[str, Any]` or `list[dict]` past the boundary
- Re-validate the same data five layers deep — validate once at the edge, trust the typed value inside

This single rule catches more real bugs than all the other typing rules combined.

## Comments and docstrings

**Comments explain WHY, not WHAT.** A comment that restates what the code does adds noise — delete it and rename the variable instead.

Acceptable comment use cases:

- Non-obvious constraints or invariants
- Workarounds with a bug or issue reference (`# Workaround for GH-123 — remove when fixed`)
- Why a specific algorithm was chosen over the obvious one
- Hidden coupling to external systems

Bad comment examples (don't write these):

```python
# WRONG — restates the code
counter = 0  # Initialize counter to zero

# WRONG — filler before an if-statement
# This statement aims to verify if a is 1
if a == 1: ...
```

**Docstrings** — reStructuredText format, on public functions/classes/modules. Skip on trivial private helpers. Module-level docstrings are optional; only write them when the module's purpose isn't obvious from the filename and imports. No file-header `Description of the Python file...` boilerplate.

## Error handling

- **Never** use bare `except:` in production code (relaxed in tests / dev scripts — see exceptions table).
- Catch specific exception types — never `except Exception:` unless re-raising or logging-and-continuing at a top-level boundary.
- **Never swallow exceptions silently.** Minimum: log them at appropriate level.
- Use `with` (context managers) or `try/finally` for resource cleanup — never rely on `__del__`.
- Validate at system boundaries (user input, file parsing, external APIs). Trust internal callers; don't defensively re-validate.

## Logging

- Use the `logging` module for any code that runs in production.
- `print` is allowed only in CLI tools (where it's the intended output) and dev/debug scripts.
- Configure log levels per environment via `logging.config`, not by editing source.
- Never log secrets, tokens, passwords, or PII.

## Testing

- **pytest** — unit and integration tests.
- Layout: `tests/` directory mirroring the package structure under `src/`.
- Test names: `test_<unit>_<scenario>_<expected>` (`test_calculate_total_zero_quantity_returns_zero`).
- Use fixtures for shared setup; avoid `setUp`/`tearDown` (unittest style).
- One assertion focus per test where practical — multiple `assert` lines are fine if they verify the same behavior.

## Project layout

```
project/
├── pyproject.toml
├── src/
│   └── <package>/
│       ├── __init__.py
│       └── ...
├── tests/
│   └── ...
└── Makefile
```

- `src/` layout (not flat) — prevents accidental imports of the working directory.
- `pyproject.toml` for config, dependencies, and tool settings.
- One package per project unless there's a strong reason for a monorepo.

## Tooling

| Concern | Tool |
|---|---|
| Format | **Ruff format** (or Black) |
| Lint | **Ruff** (replaces flake8 + isort + pyupgrade + most pylint) |
| Type check | **mypy strict** or **pyright strict** |
| Test | **pytest** |
| Dependencies | **uv** for new projects; legacy repos may stay on `pip` |

**On dependency tooling:** use `uv` whenever you're starting a new Python project. Older repos still on `pip` + `requirements.txt` are fine — don't churn them just to switch resolvers. Don't introduce `poetry` or `pipenv` to a repo that doesn't already have them.

Run before pushing:

```
make lint     # ruff check + mypy
make format   # ruff format
```

CI must run the same `make` targets so local and CI agree.

## Ignored rules (project-specific exceptions)

| Rule | Scope | Reason |
|---|---|---|
| E203 | Everywhere | Black/Ruff vs flake8 disagree on slice colons |
| D100 | Everywhere | Module docstrings not required |
| D400 | Everywhere | Don't force a period at the end of the first docstring line (multi-line docstrings allowed) |
| D205 | Everywhere | We use descriptions, not summary-line + description splits |
| F841 | DLL wrapper modules only | DLL wrapper masks require some assigned-but-unused locals |
| D101, D102, D103, D106, D200 | `tests/`, dev scripts | Docstrings not enforced in these contexts |
| E722 | `tests/`, dev scripts | Bare `except` allowed for quick scripts |

## Style and formatting

- Line length: **120 characters**.
- Spaces around operators (`=`, `&`, `|`), after commas.
- One blank line at end of file.
- Async/await: follow PEP 492. Awaitable behavior should be clear from the function name (`*_async` suffix optional but consistent within a module).

## What this skill replaces

When this skill is loaded, treat its rules as authoritative for Python work in C-Mo repos. PEP 8 still applies for anything not covered here; the rule-exceptions table above lists the explicit overrides.
