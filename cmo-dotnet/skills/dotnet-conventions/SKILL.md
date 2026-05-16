---
name: dotnet-conventions
description: Use when writing, reviewing, refactoring, or scaffolding C# / .NET Core code (>= 8.0) in C-Mo repos. Captures language rules, nullable reference types (required), CQRS layout (optional), Entity Framework Core patterns, ASP.NET Core (MVC / Web API / Blazor), JSON serialization, DI registration, logging, testing, and the tooling chain.
---

# .NET Conventions

Conventions for C# / .NET Core ≥ 8.0 in C-Mo repositories. Built on modern .NET defaults with the project-specific rules listed below. Apply these when writing, reviewing, or modifying C# code.

## C# language fundamentals

- **Nullable reference types are required.** New projects must have `<Nullable>enable</Nullable>` in the `.csproj`. Existing projects without NRTs should migrate when touched non-trivially. Never use `!` (null-forgiving operator) without a one-line justification comment explaining why null is impossible.
- **One class per file.** File name matches the type name.
- **`async`/`await`** for all I/O. Never `.Result`, `.Wait()`, or `.GetAwaiter().GetResult()` outside of `Main` or test fixtures.
- **`CancellationToken`** is the **last parameter** of every async method that performs I/O. Pass it through; never swallow it.
- **`Async` suffix** on async method names **only when** a synchronous version of the same method exists in the same type. Don't add `Async` reflexively — `Task<User> GetUser(...)` is fine when there's no `User GetUser(...)`.

## Naming

- `PascalCase` — types, public members, methods, properties, constants
- `camelCase` — locals, parameters
- `_camelCase` — private fields (single underscore prefix)
- `IPascalCase` — interfaces (only when you have one — see DI below)
- `TPascalCase` — generic type parameters
- English everywhere — names, comments, XML docs, log messages
- Enum values: full descriptive names, never abbreviations (`Approved`, not `APPR`)

## Types and nullability

- NRTs **on** in every new project.
- Public APIs annotate every reference type explicitly — `string` (non-null) vs `string?` (nullable).
- Prefer `T?` syntax over `Nullable<T>`.
- `null!` and `default!` only at framework boundaries (e.g., EF Core required navigation properties) — add an inline comment explaining the EF/framework reason.
- Pattern-match `is null` and `is not null` instead of `== null` / `!= null`.

## Project structure

```
solution/
├── src/
│   └── <Project>/              # one folder per project
│       ├── <Project>.csproj
│       └── ...
├── tests/
│   └── <Project>.Tests/        # mirrors src/<Project>
│       └── ...
└── solution.sln
```

- `src/` for production projects, `tests/` for test projects. No flat layouts.
- One class per file, namespace matches folder path.
- Folder structure inside a project reflects the bounded context, not the technical layer (avoid `Controllers/`, `Services/`, `Models/` as top-level folders when CQRS is used — see below).
- Place assembly-level metadata in `AssemblyInfo.cs` or `<Project>.csproj` directives.

## CQRS (optional — use for complex projects)

CQRS is the **default for complex domains** but **not mandatory** for every project. Simple CRUD apps don't need it. Use it when the read and write sides have clearly different requirements (different models, different scaling needs, different validation rules).

When you do use CQRS:

- Each use case is one command **or** one query, with a dedicated handler.
- Folder layout per feature: `Features/<Feature>/Commands/<Verb>{Command,Handler,Validator}.cs` and `Features/<Feature>/Queries/<Verb>{Query,Handler}.cs`. Group by feature, not by type.
- Use MediatR (or equivalent) for dispatch — wire it up in `Program.cs` via `AddMediatR(typeof(Assembly).Assembly)`.
- Commands return a `Result<T>` or a typed response — never `IActionResult`. The controller maps the handler result to HTTP.
- Queries are read-only — never call `SaveChangesAsync` from a query handler.
- Validators (FluentValidation) live next to their command and are wired into the MediatR pipeline as behavior.

For non-CQRS projects: keep controllers thin, push logic into application-layer services. Don't reach for the heavy machinery when a service class will do.

## Dependency injection

- **Stock Microsoft DI only.** Register services explicitly in `Program.cs` (or a `ServiceCollection` extension method per project). No custom `[Service]` attributes, no convention scanners — explicit registration so the wiring is greppable.
- Lifetimes:
  - **Scoped** — anything that touches the request scope or the `DbContext` (most application services).
  - **Singleton** — stateless, thread-safe utilities only. If in doubt, use Scoped.
  - **Transient** — lightweight, no shared state, cheap to construct.
- **Interfaces only when there's a real abstraction need** — multiple implementations, mocking that can't be done with concrete classes, or a true module boundary. Don't create `IFooService` purely for "good practice"; depend on the concrete class.
- Group DI registration by feature in extension methods:

  ```csharp
  public static class FeatureModuleExtensions
  {
      public static IServiceCollection AddInvoicingModule(this IServiceCollection services)
      {
          services.AddScoped<InvoiceService>();
          services.AddScoped<InvoiceValidator>();
          return services;
      }
  }
  ```

## Entity Framework Core

- **Configuration: prefer attributes over Fluent API.** Indexes, keys, lengths, table names — all on the entity class. Fluent API only when attributes can't express the configuration (value conversions, owned types, complex relationships).

  ```csharp
  [Table("invoices")]
  [Index(nameof(CustomerId), nameof(CreationTime))]
  public class Invoice
  {
      [Key] public int Id { get; set; }
      [Required, MaxLength(100)] public string Number { get; set; } = null!;  // EF will set
      public Guid CustomerId { get; set; }
      public InvoiceStatus Status { get; set; }
      public DateTime CreationTime { get; set; }
  }
  ```

- **Lazy loading: avoid.** Don't enable `LazyLoadingProxies`. Use explicit `.Include()` chains for the data you need, and **`.AsNoTracking()`** for read-only queries. Reduces N+1 surprises and makes the query intent obvious in code.
- **Owned entities** must be marked `[Required]` on the navigation, with a `= new()` initializer. Without `[Required]`, EF treats owned entities as optional and silently nullifies them if all columns are NULL — bug-prone.

  ```csharp
  [Required] public TokenUsage TokenUsage { get; set; } = new();
  ```

- **Migrations** — never edit migration `.cs`, `.Designer.cs`, or `ApplicationDbContextModelSnapshot.cs` by hand. Use `dotnet ef migrations add` / `dotnet ef migrations remove`. **Never** add raw SQL via `migrationBuilder.Sql(...)` — express schema changes through the migration DSL or write a separate, reviewed SQL script.
- **CancellationToken** on every async EF call: `await _dbContext.SaveChangesAsync(ct)`, `await query.ToListAsync(ct)`.

## ASP.NET Core — depends on the project type

C-Mo uses a mix of project types (MVC, Web API, Blazor). Apply the section that matches your project.

### MVC / Razor

- **Thin controllers.** HTTP concerns only: receive request, call application service / MediatR, return response. No business logic, no `DbContext` access from the controller.
- **Form inputs** — always use `asp-for`. Never manual `name=""` attributes for properties bound to a DTO.

  ```razor
  <input asp-for="Name" class="input" />
  <select asp-for="CategoryId" asp-items="@Model.Categories" class="select"></select>
  ```

- **Form actions** — use `asp-action` / `asp-controller`. Never `<form action="@Url.Action(...)">`.
- **View data** — typed `ViewModel` passed via `View(model)`. Never `ViewBag`. `ViewData` is acceptable for layout metadata (`Title`, breadcrumb crumbs) only.
- **URL generation** — `Url.Action(...)` in controllers/views, `LinkGenerator` in services. **Never hardcoded URL strings.**

### Web API

- Always return strongly-typed `IActionResult<T>` or `Results<T1, T2, ...>` (minimal APIs). Never return `dynamic`, `object`, or `Dictionary<string, object>`.
- DTOs in, DTOs out — never expose EF entities directly on the wire (it leaks the schema and risks circular-reference serialization).
- HTTP status code matches semantic intent: `200` only when there's a body; `204` for empty success; `400` for validation; `404` for not-found; `409` for conflict; `500` only for unhandled.
- Use `[ApiController]` on every API controller (automatic model validation, automatic `400` on invalid model state).

### Blazor

- Components in `*.razor` + `*.razor.cs` (code-behind) when the component has more than ~20 lines of logic.
- `@inject` for DI, not service locator patterns.
- Avoid heavy logic in `OnInitializedAsync` without cancellation — implement `IDisposable` or `IAsyncDisposable` for components that hold subscriptions.

### BaseController gotcha (.NET 10)

If a project has a `BaseController` with class-level `[Authorize]`, **never** put `[AllowAnonymous]` at the class level of a derived controller — .NET 10 treats class-level `[AllowAnonymous]` as overriding action-level `[Authorize]` from the base. Put `[AllowAnonymous]` on the specific actions that should be public.

## Boundary types

At any system boundary, parse incoming data into a strongly-typed object **before** passing it deeper. Boundaries include:

- HTTP request bodies (action parameters, `[FromBody]`, `[FromForm]`)
- JSON / XML / CSV file parsing
- External API responses (HttpClient + deserialize)
- Message-broker payloads
- gRPC requests/responses (the generated types are already DTOs — good)

**Use:**
- DTOs (record types or POCOs) at the edge, validated by `[ApiController]` model binding or FluentValidation.
- Domain types (entities, value objects) **inside** the boundary. Never serialize entities over the wire.

**Don't:**
- Accept `Dictionary<string, object>` or `dynamic` as a request body — lose type safety, validation, and docs.
- Return EF entities from controllers. Map to a response DTO.
- Re-validate the same DTO at every layer — validate once at the edge, then trust the typed value.

## JSON serialization

- **`System.Text.Json` is the default** for new projects — it's the built-in serializer, source-generator-friendly, faster than Newtonsoft, and natively integrated with ASP.NET Core.
- **`Newtonsoft.Json` is allowed** when:
  - A library or upstream dependency requires it.
  - Existing projects already use it and switching is non-trivial.
  - You need a specific Newtonsoft feature (e.g., `JsonConvert.PopulateObject`) that `System.Text.Json` doesn't have a clean equivalent for.
- **PascalCase in C#, camelCase on the wire.** ASP.NET Core's default serializer handles the conversion. Don't camelCase in C# to match the wire format.

  ```csharp
  // Correct
  return Ok(new { PlayerIds = ids, Message = "Done" });
  ```

## Logging

- Use `ILogger<T>` injected via constructor. Never `Console.WriteLine` in production code.
- **Structured logging** — use named placeholders, not string interpolation:

  ```csharp
  _logger.LogInformation("Invoice {InvoiceId} approved by {UserId}", invoice.Id, userId);
  // Not:
  _logger.LogInformation($"Invoice {invoice.Id} approved by {userId}");
  ```

- Never log secrets, tokens, passwords, or PII (account numbers, emails when not necessary, full request bodies that might contain credentials).
- Log levels:
  - `Trace` / `Debug` — dev only, gate behind config
  - `Information` — durable record of significant operations
  - `Warning` — recoverable anomaly
  - `Error` — failed operation, system can continue
  - `Critical` — system-wide failure

## Error handling

- **Throw specific exception types.** Never `throw new Exception(...)` in production code.
- **Never swallow exceptions.** A `try { ... } catch { }` block is a bug unless there's a comment explaining why the exception is genuinely ignorable.
- Use `try/finally` or `using` declarations for resource cleanup.
- For expected failure paths (validation, business rule violations) in CQRS handlers, prefer returning a `Result<T>` over throwing. Reserve exceptions for genuinely exceptional cases.
- At the API boundary, configure `UseExceptionHandler` or a problem-details middleware. Never leak `ex.Message` or stack traces to clients.

## Testing

Testing conventions live in dedicated skills — load them when writing or reviewing tests:

- **`cmo-core/testing-standards`** — the universal rules: tier model (Unit / Integration / Functional / Performance), two-level Jira traceability (`Task` key for unit + integration, `Requirement` key for functional / e2e), test independence and parallel execution, scenario coverage, anti-flake rules, naming, test data, source-mirror layout.
- **`cmo-dotnet/dotnet-testing`** — the .NET-specific *how*: xUnit v3 on MTP, `WebApplicationFactory<MyApp.Web.Program>`, Testcontainers wiring, AwesomeAssertions, NSubstitute, MediatR/CQRS handler patterns, Razor view-rendering and form round-trip probes, BenchmarkDotNet.

Anything previously written in this section now lives in those skills.

## URL generation

- **Never hardcoded URL strings.** Always use:
  - `Url.Action(...)` / `Url.Page(...)` in controllers and views
  - `LinkGenerator` (injected) in services
  - `asp-action` / `asp-controller` / `asp-route-*` tag helpers in Razor

  ```csharp
  // Wrong
  return Redirect("/invoices/details/5");

  // Correct
  return RedirectToAction(nameof(Details), new { id });
  ```

## Tooling

| Concern | Tool |
|---|---|
| Format | `dotnet format` |
| Style enforcement | `.editorconfig` + Roslyn analyzers (built-in) |
| Style enforcement (optional) | StyleCop.Analyzers as a PackageReference |
| Test | xUnit v3 on MTP + AwesomeAssertions — see `cmo-dotnet/dotnet-testing` |
| Mocking | NSubstitute — see `cmo-dotnet/dotnet-testing` |
| Coverage | Coverlet + ReportGenerator |
| Build | `dotnet build /warnaserror` — warnings fail the build |

Run before pushing:

```
dotnet format --verify-no-changes
dotnet build /warnaserror
dotnet test
```

CI must run the same commands.

## Library and documentation research

- Use **WebSearch**, **WebFetch**, or **Context7 MCP tools** (`resolve-library-id`, `query-docs`) to look up library usage.
- **Never** browse `~/.nuget/packages/...` to figure out how a library works. Those are decompiled binaries / raw implementation, not documentation. They're slow to read, unreliable, and a token sink.

## File operations

- **Always use `git mv`** to rename or move tracked files. Never delete and recreate — it loses history and produces noisier diffs.

## Quick reference

| Aspect | Rule |
|---|---|
| Nullable reference types | **Required** in new projects |
| `Async` suffix | Only when a sync version of the same method exists |
| File organization | One class per file |
| Async I/O | Always `async`/`await`; never `.Result` / `.Wait()` |
| `CancellationToken` | Last param of every I/O-bound async method |
| DI registration | Explicit `AddScoped/Singleton/Transient` in `Program.cs` — no convention scanners |
| Interfaces | Only when there's a real abstraction need |
| CQRS | Default for complex projects, not mandatory |
| EF Core config | Attributes over Fluent API |
| EF Core lazy loading | **Disabled**; use explicit `Include` + `AsNoTracking` for reads |
| EF Core owned entities | `[Required]` + `= new()` |
| EF migrations | `dotnet ef` only; no manual edits; no raw SQL |
| JSON default | `System.Text.Json`; Newtonsoft only when legacy/library forces it |
| JSON property naming | PascalCase in C# — serializer handles wire format |
| URL generation | `Url.Action` / `LinkGenerator` / tag helpers; never hardcoded |
| Form inputs (MVC) | Always `asp-for`; never manual `name` |
| View data (MVC) | Typed `ViewModel`; never `ViewBag` |
| API responses | Strongly-typed; never `dynamic` / `Dictionary<string, object>` |
| Logging | `ILogger<T>`, structured placeholders, never log secrets |
| Exceptions | Throw specific types; never swallow; never leak details at the boundary |
| Tests | See `cmo-core/testing-standards` (universal rules) + `cmo-dotnet/dotnet-testing` (.NET specifics) |
| Build | `/warnaserror` — warnings fail the build |
| Library docs | WebSearch / Context7 — never read `~/.nuget/` source |
| File moves | Always `git mv` |
| `BaseController` | Class-level `[AllowAnonymous]` overrides base `[Authorize]` in .NET 10 — apply at action level instead |
