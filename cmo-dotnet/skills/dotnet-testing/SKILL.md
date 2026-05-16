---
name: dotnet-testing
description: Testing standards for any C# / .NET project — Web API, Razor / MVC, Blazor, worker services, libraries. Covers unit, integration, functional/e2e (Playwright), and performance (BenchmarkDotNet) tiers; xUnit + `WebApplicationFactory<Program>`; Testcontainers for DB / broker / object-store fidelity; CQRS handler patterns; Razor view-rendering and form round-trip probes; test independence and parallelism. Use when writing, reviewing, or scaffolding tests; when wiring fixtures and mocks; when designing test CI. Pairs with `dotnet-conventions`.
---

# .NET Testing Standards

Tiered testing for any .NET project. Each tier has a dedicated test project, a single runner (xUnit v3), and a clear scope.

| Tier | Project suffix | Scope | Stack |
|---|---|---|---|
| Unit | `*.UnitTests` | Pure logic — handlers, validators, services, value objects, helpers. No host, no I/O. | xUnit v3 + AwesomeAssertions + NSubstitute |
| Integration | `*.IntegrationTests` | Real ASP.NET Core pipeline in-process via `WebApplicationFactory<Program>`. Real DB / broker / object store via **Testcontainers**. Covers policy/auth, validators, model binding, MediatR pipeline, EF migrations. **Every API endpoint must be exercised here with all its scenarios.** | xUnit v3 + `Microsoft.AspNetCore.Mvc.Testing` + Testcontainers |
| Functional / e2e | `*.FunctionalTests` | **Browser-based end-to-end tests via Playwright** — only for projects that serve a web UI (Razor / Blazor / MVC views / SPA backends). Login flows, JS interactions, redirects. Web API projects do not have a functional tier. | xUnit v3 + Microsoft.Playwright |
| Performance | `*.Benchmarks` | Micro-benchmarks of hot paths (view rendering, hot service methods, allocation hotspots). | BenchmarkDotNet console app |

Split into separate projects from day one. Mixing tiers in a single `*.Tests` project costs you CI flexibility, runtime, and the ability to gate slow tests behind a different cadence.

---

## Hard rules (apply to every test, every project)

- **Tests are independent and run in parallel.** No test depends on another test's state, ordering, or side effects. Each test owns its data — seed what it needs, clean up nothing (the fixture or per-test DB does that). xUnit runs collections in parallel by default; do **not** disable parallelism with `[CollectionDefinition(DisableParallelization = true)]` unless you have a concrete reason and a comment explaining it. If two tests interact, one of them is buggy.
- **Test class naming `{Subject}Tests`**, test method `Method_Condition_Result` (e.g. `Approve_PendingInvoice_SetsStatusApproved`). Test files mirror the source folder structure.
- **Nullable reference types enabled** (`<Nullable>enable</Nullable>`). Test code may use `string?` and friends where framework / library APIs return nullable; that's the only exception to the "annotate everything explicitly" rule from `dotnet-conventions`.
- **`async`/`await` all the way down.** Pass `TestContext.Current.CancellationToken` (xUnit v3) to every async API that accepts one — the `xUnit1051` analyzer warns when you don't.
- **No `Thread.Sleep`, no arbitrary delays.** If a test is flaky on timing, the production code has a race. Fix the race, not the test.
- **One assertion concept per test.** Multiple `.Should()` calls are fine if they verify the same logical outcome.
- **Traceability — two levels, tier-dependent.** Required for regulated projects, optional for internal-only projects.
  - **Required** (medical-device software, customer-facing backends, anything under an IEC 62304 / regulatory audit trail): every test method carries a trait linking it to a Jira issue. The trait key depends on the tier:
    - **Unit + Integration tests** → `[Trait(Traits.Task, "SW-XXXX")]` — links to a Jira issue of type **Task** (the work item that introduced the behaviour).
    - **Functional / e2e tests** → `[Trait(Traits.Requirement, "SW-XXXX")]` — links to a Jira issue of type **Requirement** (the user-facing capability the journey verifies).
    - Both keys point at the same Jira project; the issue *type* (Task vs Requirement) tells the audit trail what level of contract the test is verifying.
    - Tests that don't map to a single Jira issue (route-sanity probes, log-assertion teardowns) use `[Trait(Traits.Task, "SW-INFRA")]` or another agreed sentinel — never omit the trait at the required tier.
  - **Optional** (internal tools, dev tooling, throwaway experiments): skip both traits entirely — don't fake IDs to "look compliant".
  - If the project's README / `CLAUDE.md` is silent and the project ships software to a regulated context, **assume traceability is required**.

---

## SDK & runner setup

### `global.json` — opt into the Microsoft Testing Platform

On **.NET 10 SDK and later**, `dotnet test` no longer falls back to VSTest. Every solution using xUnit v3 / MTP must opt in at the repo root:

```jsonc
{
  "sdk": {
    "version": "10.0.100",
    "rollForward": "latestFeature"
  },
  "test": {
    "runner": "Microsoft.Testing.Platform"
  }
}
```

Without the `"test"` block, the runner errors with `Testing with VSTest target is no longer supported by Microsoft.Testing.Platform on .NET 10 SDK and later.`

### `Program.cs` must be discoverable

`WebApplicationFactory<TEntryPoint>` requires `TEntryPoint` to be a real class. Top-level statements put `Program` in the global namespace and out of test code's reach. Append this to the end of `Program.cs`, in a braced namespace:

```csharp
app.Run();

namespace MyApp.Web
{
    public partial class Program { }
}
```

File-scoped namespaces (`namespace MyApp.Web;`) **don't work** here — CS8956: a file-scoped namespace can't follow top-level statements. Always reference the type as `WebApplicationFactory<MyApp.Web.Program>` in tests so it doesn't collide with a sibling `Program` (e.g. in `*.Benchmarks`).

### Test csproj boilerplate every tier needs

```xml
<PropertyGroup>
  <TargetFramework>net10.0</TargetFramework>
  <!-- Test SDK does NOT enable ImplicitUsings by default — without this you get CS0246 on Task, HttpClient, IEnumerable. -->
  <ImplicitUsings>enable</ImplicitUsings>
  <Nullable>enable</Nullable>
  <IsPackable>false</IsPackable>
  <IsTestProject>true</IsTestProject>
  <!-- MTP test hosts are executables. -->
  <OutputType>Exe</OutputType>
</PropertyGroup>
```

---

## Shared per-project files

### `Usings.cs` *(every project)*

Global usings for things every test in the assembly needs.

```csharp
global using Xunit;
global using AwesomeAssertions;
global using NSubstitute;
```

### `Traits.cs` *(only in projects that use traits)*

Ship this when the project requires traceability **or** uses trait keys for filtering (`Category`, `Speed`, etc.). Internal-only projects without traceability can skip the file. Exposes both `Task` and `Requirement` keys so each tier picks the right one:

```csharp
namespace MyApp.UnitTests;

public static class Traits {
    /// <summary>Jira issue of type "Task" — used on unit and integration tests.</summary>
    public const string Task = "task";

    /// <summary>Jira issue of type "Requirement" — used on functional / e2e tests.</summary>
    public const string Requirement = "requirement";

    // Add other keys here (Category, Speed, …) — never invent ad-hoc strings.
}
```

---

## Tier 1 — Unit Tests

Pure, fast, no I/O. Target: < 1 ms each.

### Stack

- **xUnit v3** on MTP — reference `xunit.v3`. Do **not** add `xunit.v3.mtp-v2` separately; `xunit.v3` already pulls in `xunit.v3.mtp-v1`, and the two conflict at compile time.
- **`xunit.analyzers`** (not `xunit.v3.analyzers` — that package doesn't exist) — catches swapped `Assert.Equal` args, missing `await`, empty `[Theory]` data, etc.
- **AwesomeAssertions** for readable assertions (`result.Should().Be(...)`). Apache-2.0 fork of FluentAssertions v7, drop-in API-compatible. Do **not** use FluentAssertions v8+ — Xceed commercial license.
- **NSubstitute** for mocks/stubs. Prefer over Moq — terser, no lambdas for properties.
- **`Microsoft.Extensions.Diagnostics.Testing`** for `FakeLoggerProvider` when asserting log output.

### Csproj fragment

```xml
<ItemGroup>
  <PackageReference Include="xunit.v3" />
  <PackageReference Include="xunit.analyzers" />
  <PackageReference Include="AwesomeAssertions" />
  <PackageReference Include="NSubstitute" />
</ItemGroup>
<ItemGroup>
  <ProjectReference Include="..\..\src\MyApp.Core\MyApp.Core.csproj" />
</ItemGroup>
```

### Pattern — service with NSubstitute

```csharp
public class InvoiceServiceTests {
    private readonly IInvoiceRepository _repository = Substitute.For<IInvoiceRepository>();
    private readonly InvoiceService _sut;

    public InvoiceServiceTests() => _sut = new InvoiceService(_repository);

    [Fact]
    [Trait(Traits.Task, "SW-1234")] // Jira Task that introduced this behaviour (regulated projects only)
    public async Task Approve_PendingInvoice_SetsStatusApproved() {
        var invoice = new Invoice { Status = InvoiceStatus.Pending };

        await _sut.ApproveAsync(invoice, TestContext.Current.CancellationToken);

        invoice.Status.Should().Be(InvoiceStatus.Approved);
        await _repository.Received(1).SaveChangesAsync(TestContext.Current.CancellationToken);
    }

    [Fact]
    public async Task Approve_NonPendingInvoice_Throws() {
        var invoice = new Invoice { Status = InvoiceStatus.Approved };

        var act = () => _sut.ApproveAsync(invoice, TestContext.Current.CancellationToken);

        await act.Should().ThrowAsync<InvalidOperationException>();
    }
}
```

### Pattern — MediatR command handler with EF Core InMemory

`Microsoft.EntityFrameworkCore.InMemory` is **only** acceptable for trivial handler tests where the queries are basic CRUD. It does not enforce foreign keys, unique constraints, or any relational invariant, and it does not translate queries (it's LINQ-to-Objects). The moment the test depends on FK enforcement, a unique index, a raw SQL expression, or a migration — promote it to an integration test (Testcontainers).

```csharp
public class CreateInvoiceCommandHandlerTests {
    private static AppDbContext NewContext() {
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseInMemoryDatabase($"db-{Guid.NewGuid()}")
            .Options;
        return new AppDbContext(options);
    }

    [Fact]
    public async Task Handle_PersistsInvoice_AndReturnsId() {
        using var db = NewContext();
        var handler = new CreateInvoiceCommandHandler(db);

        var id = await handler.Handle(
            new CreateInvoiceCommand { CustomerId = Guid.NewGuid(), Amount = 100m },
            TestContext.Current.CancellationToken);

        var stored = await db.Invoices.SingleAsync(TestContext.Current.CancellationToken);
        stored.Id.Should().Be(id);
        stored.Amount.Should().Be(100m);
    }
}
```

Each test gets a unique InMemory database name (`$"db-{Guid.NewGuid()}"`) — never share a name across tests in the same class, or you defeat the parallelism / independence rule.

### Rules

- **No `WebApplicationFactory`, no real DB, no `HttpClient`** in unit tests — that's the integration tier.
- **`[Theory]` + `[InlineData]`** for parameterised tests. Never branch on input inside the test body.
- **Use a builder helper or `Bogus`** for non-trivial test data. Avoid hand-rolled object literals scattered across files.

---

## Tier 2 — Integration Tests

Runs the real ASP.NET Core pipeline in-process via `WebApplicationFactory<MyApp.Web.Program>`. This is the workhorse tier — catches broken policies, broken validators, broken routes, broken EF migrations, and broken MediatR wiring.

**Coverage rule**: **every API endpoint shall be tested at this tier by calling it directly with all its scenarios** — happy path, validation failures, authorisation failures (each role / policy / requirement), not-found, conflict, and any domain-specific error path. Endpoint coverage is the definition of "done" for new controllers.

### Stack

- **xUnit v3** (same setup as Tier 1).
- **`Microsoft.AspNetCore.Mvc.Testing`** — provides `WebApplicationFactory<TEntryPoint>` and `TestServer`.
- **Testcontainers** for **every external dependency** that has one (database, message broker, object store, mail server). Use the provider that matches production — `Testcontainers.PostgreSql`, `Testcontainers.MsSql`, `Testcontainers.MySql`, `Testcontainers.Redis`, `Testcontainers.RabbitMq`, LocalStack for S3, etc. One container per fixture, started in `IAsyncLifetime.InitializeAsync`, killed in `DisposeAsync`. Do not substitute SQLite-in-memory for a real provider — it lies about provider-specific behaviour (`jsonb`, snake-case identifiers, partial indexes, real FK timing, …) and the test gives you false confidence.
- **AngleSharp** *(Razor / MVC / Blazor projects only)* for HTML parsing and CSS-selector assertions on rendered views.
- **`Respawn`** for fast per-test DB cleanup — truncates user tables while keeping the schema and migration state, far cheaper than dropping and recreating the database.
- **`Microsoft.Extensions.Diagnostics.Testing`** for `FakeLoggerProvider` — assert no `Warning+` logs leak from a successful request.

### Csproj fragment

```xml
<ItemGroup>
  <FrameworkReference Include="Microsoft.AspNetCore.App" />
  <PackageReference Include="xunit.v3" />
  <PackageReference Include="xunit.analyzers" />
  <PackageReference Include="AwesomeAssertions" />
  <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" />
  <PackageReference Include="Testcontainers.PostgreSql" />
  <PackageReference Include="Respawn" />
  <PackageReference Include="Microsoft.Extensions.Diagnostics.Testing" />
  <!-- Razor / Blazor only: -->
  <PackageReference Include="AngleSharp" />
</ItemGroup>
<ItemGroup>
  <ProjectReference Include="..\..\src\MyApp.Web\MyApp.Web.csproj" />
</ItemGroup>
```

### Pattern — `WebApplicationFactory` + Testcontainers fixture

Consolidate the host wiring in **one** base fixture per project. Tests extend it; they don't duplicate `WithWebHostBuilder` blocks.

```csharp
public class WebFactoryFixture : WebApplicationFactory<MyApp.Web.Program>, IAsyncLifetime {
    private readonly PostgreSqlContainer _db = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();
    private Respawner _respawner = default!;

    public async ValueTask InitializeAsync() {
        await _db.StartAsync();
        using var scope = Services.CreateScope();
        var ctx = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await ctx.Database.MigrateAsync();
        _respawner = await Respawner.CreateAsync(_db.GetConnectionString(),
            new RespawnerOptions { DbAdapter = DbAdapter.Postgres });
    }

    public Task ResetDatabaseAsync() => _respawner.ResetAsync(_db.GetConnectionString());

    public override async ValueTask DisposeAsync() {
        await base.DisposeAsync();
        await _db.DisposeAsync();
    }

    protected override void ConfigureWebHost(IWebHostBuilder builder) {
        builder.UseSetting("ConnectionStrings:Default", _db.GetConnectionString());
        builder.ConfigureServices(services => services.AddLogging(b => b.AddFakeLogging()));
        builder.UseEnvironment("Testing");
    }
}
```

Call `await Factory.ResetDatabaseAsync()` in the base class's constructor — xUnit v3 creates a new test class instance per test, so this gives every test a clean DB without paying the cost of dropping and recreating it.

### Pattern — test auth handler (when the endpoint requires auth)

Auth bypass via a global flag is never acceptable. Inject a test auth handler so the real authorisation pipeline runs.

```csharp
public class TestAuthHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder) {

    public const string SchemeName = "Test";

    protected override Task<AuthenticateResult> HandleAuthenticateAsync() {
        // The test sets these via a request header (or a per-scope claim accessor).
        if (!Request.Headers.TryGetValue("X-Test-Role", out var role)) {
            return Task.FromResult(AuthenticateResult.NoResult());
        }
        var claims = new List<Claim> {
            new(ClaimTypes.NameIdentifier, Request.Headers["X-Test-UserId"].ToString()),
            new(ClaimTypes.Role, role.ToString()),
        };
        var ticket = new AuthenticationTicket(
            new ClaimsPrincipal(new ClaimsIdentity(claims, SchemeName)), SchemeName);
        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
```

Register it in the fixture's `ConfigureWebHost` via `services.AddAuthentication(...).AddScheme<AuthenticationSchemeOptions, TestAuthHandler>(...)` (override the default scheme name). Tests then set `client.DefaultRequestHeaders.Add("X-Test-Role", "Admin")` per scenario.

### Pattern — Web API endpoint integration test

```csharp
public class CreateInvoiceEndpointTests : IClassFixture<WebFactoryFixture> {
    private readonly WebFactoryFixture _factory;

    public CreateInvoiceEndpointTests(WebFactoryFixture factory) {
        _factory = factory;
    }

    private HttpClient AuthedClient(string role) {
        var client = _factory.CreateClient();
        client.DefaultRequestHeaders.Add("X-Test-Role", role);
        client.DefaultRequestHeaders.Add("X-Test-UserId", Guid.NewGuid().ToString());
        return client;
    }

    [Fact]
    [Trait(Traits.Task, "SW-1234")] // Integration tests link to the Jira Task — same key as unit tests
    public async Task Create_AsAdmin_ReturnsCreated() {
        await _factory.ResetDatabaseAsync();
        var client = AuthedClient("Admin");
        var body = JsonContent.Create(new CreateInvoiceCommand { CustomerId = Guid.NewGuid(), Amount = 100m });

        var response = await client.PostAsync("/api/v1/invoices", body, TestContext.Current.CancellationToken);

        response.StatusCode.Should().Be(HttpStatusCode.Created);
        var id = await response.Content.ReadFromJsonAsync<Guid>(TestContext.Current.CancellationToken);
        id.Should().NotBe(Guid.Empty);
    }

    [Theory]
    [InlineData("Viewer")]
    [InlineData("Auditor")]
    public async Task Create_AsNonAdmin_ReturnsForbidden(string role) {
        var client = AuthedClient(role);
        var body = JsonContent.Create(new CreateInvoiceCommand { CustomerId = Guid.NewGuid(), Amount = 100m });

        var response = await client.PostAsync("/api/v1/invoices", body, TestContext.Current.CancellationToken);

        response.StatusCode.Should().Be(HttpStatusCode.Forbidden);
    }

    [Fact]
    public async Task Create_WithMissingCustomer_ReturnsBadRequest() {
        var client = AuthedClient("Admin");
        var body = JsonContent.Create(new { Amount = 100m }); // CustomerId missing

        var response = await client.PostAsync("/api/v1/invoices", body, TestContext.Current.CancellationToken);

        response.StatusCode.Should().Be(HttpStatusCode.BadRequest);
    }

    [Fact]
    public async Task Create_Unauthenticated_ReturnsUnauthorized() {
        var client = _factory.CreateClient(); // no test-auth header
        var body = JsonContent.Create(new CreateInvoiceCommand { CustomerId = Guid.NewGuid(), Amount = 100m });

        var response = await client.PostAsync("/api/v1/invoices", body, TestContext.Current.CancellationToken);

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
```

This is the **minimum** scenario coverage for a write endpoint: success, authorisation failure for every non-allowed role, validation failure, and unauthenticated. Read endpoints add not-found and (where relevant) authorisation-by-resource-ownership scenarios. **No endpoint ships without this coverage.**

### Pattern — route-sanity probe

A single test that walks every action descriptor and asks `LinkGenerator` to resolve a URL. Cheap, no HTTP — catches dead routes (broken `[Route]` attributes, tag-helper `asp-action` typos) before they hit a view or a redirect.

```csharp
public class RouteSanityTests : IClassFixture<WebFactoryFixture> {
    private readonly WebFactoryFixture _factory;
    public RouteSanityTests(WebFactoryFixture factory) => _factory = factory;

    [Fact]
    public void AllActionDescriptors_ResolveToAUrl() {
        using var scope = _factory.Services.CreateScope();
        var actions = scope.ServiceProvider.GetRequiredService<IActionDescriptorCollectionProvider>();
        var links = scope.ServiceProvider.GetRequiredService<LinkGenerator>();

        foreach (var d in actions.ActionDescriptors.Items.OfType<ControllerActionDescriptor>()) {
            var url = links.GetPathByAction(action: d.ActionName, controller: d.ControllerName);
            url.Should().NotBeNullOrEmpty(
                $"{d.ControllerName}.{d.ActionName} has no resolvable route");
        }
    }
}
```

### Pattern — log-assertion teardown (no silent server errors)

Fail any integration test that logs at `Warning+` during the request. Strong "no silent server errors" guarantee.

```csharp
public abstract class IntegrationTestBase : IClassFixture<WebFactoryFixture>, IDisposable {
    protected WebFactoryFixture Factory { get; }
    protected HttpClient Client { get; }
    private readonly FakeLogCollector _logs;

    protected IntegrationTestBase(WebFactoryFixture factory) {
        Factory = factory;
        Client = factory.CreateClient();
        _logs = factory.Services.GetRequiredService<FakeLogCollector>();
        _logs.Clear();
    }

    public void Dispose() {
        var problems = _logs.GetSnapshot()
            .Where(r => r.Level >= LogLevel.Warning)
            .ToList();
        problems.Should().BeEmpty("the request logged warnings or errors");
    }
}
```

### Razor / MVC / Blazor patterns *(skip for Web-API-only projects)*

For projects that render server-side views (or hybrid Blazor with server rendering), tag helpers and form bindings silently render wrong / empty output when broken — you only learn about it at runtime. These two patterns catch the breakage at PR time.

#### View rendering with AngleSharp (catches broken `asp-action` / `asp-controller`)

```csharp
[Fact]
public async Task Index_RendersDetailsLink_WithResolvedRoute() {
    var response = await Client.GetAsync("/Invoices", TestContext.Current.CancellationToken);
    response.EnsureSuccessStatusCode();

    var document = await BrowsingContext.New(Configuration.Default)
        .OpenAsync(req => req.Content(await response.Content.ReadAsStringAsync(TestContext.Current.CancellationToken)));

    var link = document.QuerySelector("a.invoice-details-link");
    // A broken asp-action renders href="" instead of throwing — asserting on the
    // resolved href is the cheapest way to catch it.
    link!.GetAttribute("href").Should().StartWith("/Invoices/Details/");
}
```

#### Form round-trip test (catches binding-prefix / wrong `[FromX]` source / culture parse bugs)

Three real bugs at once:

1. **Prefix mismatch.** `<input asp-for="@abc.Property" />` renders `name="abc.Property"`; the model binder uses the action's parameter name as the prefix. Renaming the parameter silently breaks the form.
2. **Wrong binding source.** `Create([FromQuery] InvoiceForm payload)` expects query-string values; form-encoded POST data won't bind.
3. **Culture-sensitive parsing.** Model binding parses decimals and dates with the request's `CurrentCulture`, not invariant — `"42.50"` binds to `0m` on a `pt-PT` machine.

The test renders the form, harvests every `name` attribute the renderer emitted, POSTs those exact names back, and asserts the action's parameter was populated. The diagnostic message distinguishes prefix mismatch, wrong source, culture parse, and validation failure.

```csharp
public class CapturedBindings {
    public ConcurrentDictionary<string, IDictionary<string, object?>> ByCorrelationId { get; } = new();
}

public class CapturedBindingFilter(CapturedBindings store) : IActionFilter {
    public const string HeaderName = "X-Test-CorrelationId";
    public void OnActionExecuting(ActionExecutingContext context) {
        if (context.HttpContext.Request.Headers.TryGetValue(HeaderName, out var id) && !string.IsNullOrEmpty(id)) {
            store.ByCorrelationId[id!] = new Dictionary<string, object?>(context.ActionArguments);
        }
    }
    public void OnActionExecuted(ActionExecutedContext context) { }
}
```

Wire `CapturedBindings` + `CapturedBindingFilter` in the fixture; pin the culture to invariant:

```csharp
CultureInfo.DefaultThreadCurrentCulture = CultureInfo.InvariantCulture;
services.AddSingleton<CapturedBindings>();
services.AddSingleton<CapturedBindingFilter>();
services.Configure<MvcOptions>(o => o.Filters.AddService<CapturedBindingFilter>());
```

The test:

```csharp
[Fact]
public async Task Create_FormRoundTrip_BindsAllRenderedInputsToController() {
    var correlationId = Guid.NewGuid().ToString();
    var client = Factory.CreateClient(new() { AllowAutoRedirect = false });
    client.DefaultRequestHeaders.Add(CapturedBindingFilter.HeaderName, correlationId);

    var getResp = await client.GetAsync("/Invoices/Create", TestContext.Current.CancellationToken);
    var document = await BrowsingContext.New(Configuration.Default)
        .OpenAsync(req => req.Content(await getResp.Content.ReadAsStringAsync(TestContext.Current.CancellationToken)));
    var form = (IHtmlFormElement)document.QuerySelector("form")!;

    var sample = new Dictionary<string, string> { ["Number"] = "INV-001", ["Amount"] = "42.50" };
    var fields = new Dictionary<string, string>();
    foreach (var el in form.QuerySelectorAll("input[name], select[name], textarea[name]")) {
        if (el.GetAttribute("type") is "submit" or "button") continue;
        var name = el.GetAttribute("name")!;
        var leaf = name.Contains('.') ? name[(name.LastIndexOf('.') + 1)..] : name;
        fields[name] = sample.TryGetValue(leaf, out var v) ? v : "x";
    }

    var postResp = await client.PostAsync(form.GetAttribute("action"),
        new FormUrlEncodedContent(fields), TestContext.Current.CancellationToken);

    var captured = Captured.ByCorrelationId.GetValueOrDefault(correlationId);
    var bound = captured?.Values.OfType<InvoiceForm>().FirstOrDefault();
    var diagnostic = captured is null
        ? "filter never ran — antiforgery or pipeline blocked the POST"
        : bound is null
            ? $"action ran but no InvoiceForm in args. Args: [{string.Join(",", captured.Keys)}] — prefix mismatch?"
            : $"DTO bound: Number='{bound.Number}' Amount={bound.Amount} — validation failed or culture parse failed";

    postResp.StatusCode.Should().Be(HttpStatusCode.Redirect, diagnostic);
    bound!.Number.Should().Be("INV-001");
    bound.Amount.Should().Be(42.50m);
}
```

Key design choices:

- **Address the bound DTO by *type*, not by parameter name** — resilient to action-parameter renames while still failing if no field-name prefix matches.
- **`AllowAutoRedirect = false` is mandatory** — without it the client follows the 302 and the success signal is masked.
- **`CultureInfo.DefaultThreadCurrentCulture` in `ConfigureWebHost` is the only reliable culture pin** — `Accept-Language` does nothing unless the app uses `UseRequestLocalization`.
- **Register the filter as a service** via `o.Filters.AddService<T>()`, not `o.Filters.Add<T>()` — otherwise it's a fresh instance per request and the singleton store is unreachable.

### Integration tier — additional rules

- **Use `IClassFixture<WebFactoryFixture>`** so the host is built once per class, not per test.
- **Never share Testcontainers instances across parallel xUnit collections** — give each collection its own fixture or you get port collisions.
- **Anonymous DTOs in `Json()` responses use PascalCase in C#** — ASP.NET converts to camelCase on the wire. Assert against the camelCase JSON.
- **URL assertions are the one place** the "no hardcoded URLs" rule from `dotnet-conventions` is relaxed — you're asserting on the rendered URL, not constructing one.

---

## Tier 3 — Functional / End-to-End (Playwright)

**Only for projects that serve a web UI** — Razor / Blazor / MVC views / SPA backends. Web API projects have no functional tier; their end-to-end is exhausted by the integration tier.

Use sparingly: these tests are the slowest tier and the most brittle. One smoke test of every critical user journey, not full coverage.

### Stack

- **Microsoft.Playwright** (.NET binding) + **xUnit v3**.
- **A real Kestrel host on a random port** — *not* `WebApplicationFactory<TEntryPoint>`. `WebApplicationFactory` uses `TestServer`, which is an in-memory request handler with no HTTP listener; Playwright drives a real browser to a real URL.

### Csproj fragment

```xml
<ItemGroup>
  <FrameworkReference Include="Microsoft.AspNetCore.App" />
  <PackageReference Include="xunit.v3" />
  <PackageReference Include="xunit.analyzers" />
  <PackageReference Include="AwesomeAssertions" />
  <PackageReference Include="Microsoft.Playwright" />
</ItemGroup>
```

After `dotnet build`, install the browsers. Preferred:

```bash
pwsh tests/MyApp.FunctionalTests/bin/Debug/net10.0/playwright.ps1 install chromium
```

If `pwsh` isn't available (common on macOS dev machines), call `Microsoft.Playwright.Program.Main(["install", "chromium"])` from the fixture's `InitializeAsync` (idempotent). Do **not** use `dotnet exec ... Microsoft.Playwright.dll install` — the DLL has no `runtimeconfig.json` and that invocation fails with a self-contained-app error.

In CI, pre-install browsers in a workflow step so the install cost isn't counted against test wall-clock.

### Pattern — Kestrel-hosted fixture

```csharp
public class KestrelHostFixture : IAsyncLifetime {
    private readonly PostgreSqlContainer _db = new PostgreSqlBuilder().WithImage("postgres:16-alpine").Build();
    private WebApplication? _app;

    public string BaseUrl { get; private set; } = default!;

    public async ValueTask InitializeAsync() {
        await _db.StartAsync();
        // ApplicationName + ContentRootPath must point at the web project's bin output, otherwise
        // MapStaticAssets() can't find <ApplicationName>.staticwebassets.endpoints.json on .NET 10.
        var webBin = Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory, "..", "..", "..", "..", "..",
            "src", "MyApp.Web", "bin", "Debug", "net10.0"));
        var builder = WebApplication.CreateBuilder(new WebApplicationOptions {
            ContentRootPath = webBin,
            ApplicationName = "MyApp.Web",
        });
        builder.Configuration["ConnectionStrings:Default"] = _db.GetConnectionString();
        MyApp.Web.Program.ConfigureServices(builder);

        _app = builder.Build();
        MyApp.Web.Program.ConfigurePipeline(_app);
        _app.Urls.Add("http://127.0.0.1:0");
        await _app.StartAsync();
        BaseUrl = _app.Urls.First();
    }

    public async ValueTask DisposeAsync() {
        if (_app is not null) { await _app.StopAsync(); await _app.DisposeAsync(); }
        await _db.DisposeAsync();
    }
}
```

This pattern requires the production `Program.cs` to expose `ConfigureServices(builder)` and `ConfigurePipeline(app)` helpers so the fixture can build the same host without duplicating setup.

### Pattern — Playwright test

```csharp
[Fact]
[Trait(Traits.Requirement, "SW-5678")] // Functional tests link to the Jira Requirement — NOT the Task
public async Task Login_WithValidCredentials_RedirectsToDashboard() {
    using var pw = await Playwright.CreateAsync();
    await using var browser = await pw.Chromium.LaunchAsync(new() { Headless = true });
    var context = await browser.NewContextAsync(new() { BaseURL = Host.BaseUrl });
    var page = await context.NewPageAsync();

    await page.GotoAsync("/Account/Login");
    await page.FillAsync("[data-testid='email']", "admin@example.com");
    await page.FillAsync("[data-testid='password']", "Password1!");
    await page.ClickAsync("[data-testid='submit']");

    await page.WaitForURLAsync("**/Dashboard");
    await Assertions.Expect(page.Locator("[data-testid='dashboard-title']")).ToHaveTextAsync("Dashboard");
}
```

### Functional tier — rules

- **Selectors: `[data-testid="..."]`** (or `[data-cy="..."]`). Never assert on CSS classes used for styling.
- **Enable Playwright tracing on failure only** via env var `PLAYWRIGHT_TRACING=1`; upload traces as CI artifacts. Tracing is too expensive to leave on by default.
- **Don't reuse login state across unrelated test classes.** Each fixture either logs in fresh or uses `storageState` from a one-time setup.
- **One critical journey per test**, not full coverage. Detailed coverage belongs in the integration tier.

---

## Tier 4 — Performance / Benchmarks

`BenchmarkDotNet` console project. Used for measuring hot paths and detecting regressions — add only when a hot path is identified.

```xml
<PropertyGroup>
  <OutputType>Exe</OutputType>
  <IsPackable>false</IsPackable>
  <IsTestProject>false</IsTestProject>
  <ServerGarbageCollection>true</ServerGarbageCollection>
</PropertyGroup>
<ItemGroup>
  <PackageReference Include="BenchmarkDotNet" />
</ItemGroup>
```

```csharp
public static class Program {
    public static void Main(string[] args) =>
        BenchmarkSwitcher.FromAssembly(typeof(Program).Assembly).Run(args);
}

[MemoryDiagnoser]
public class InvoiceRenderingBenchmark {
    [Benchmark(Baseline = true)]
    public string OldImplementation() { /* … */ }

    [Benchmark]
    public string NewImplementation() { /* … */ }
}
```

### Rules

- **Never run benchmarks inside Docker, inside a shared CI runner, or alongside other workloads.** You need a stable CPU and scheduler. Dedicated machine, scheduled cadence (nightly / on-demand), results posted to a tracking issue.
- **Always include `[MemoryDiagnoser]`** — allocation regressions matter as much as time regressions.
- **`[GlobalSetup]` for once-per-method setup; `[IterationSetup]` for per-iteration.** Never put expensive setup inside the `[Benchmark]` method.
- **Within ~3% of an alternative is noise** — don't optimise based on that delta.

---

## Docker / Testcontainers policy

Use Docker to host **the dependencies the tests need**, not the test runner itself.

- **Unit tests** — no Docker.
- **Integration tests** — Testcontainers per fixture (`PostgreSql`, `MsSql`, `MySql`, `Redis`, `RabbitMq`, LocalStack for S3, …). Match production providers exactly.
- **Functional tests** — in-process Kestrel + Playwright-managed browsers. Container only if you need to pin the browser OS (`mcr.microsoft.com/playwright/dotnet`).
- **Benchmarks** — never in Docker.

Avoid `docker-compose up` for tests — shared state across runs defeats the per-fixture isolation Testcontainers gives you.

---

## CI layout

Run each tier on its own cadence:

| Workflow | Tier | When |
|---|---|---|
| `unit.yml` | Unit | Every push (PR + main) |
| `integration.yml` | Integration | Every PR (matrix by DB provider if multiple) |
| `functional.yml` | Functional | Every PR (Chromium only); main + nightly (all browsers) |
| `benchmarks.yml` | Benchmarks | Nightly on a dedicated runner; results posted to a tracking issue |

Filter via `dotnet test --filter` on traits, project, or class — never by test name patterns.

```bash
# MTP: --project, not positional
dotnet test --project tests/MyApp.UnitTests/MyApp.UnitTests.csproj
dotnet test --project tests/MyApp.IntegrationTests/MyApp.IntegrationTests.csproj
dotnet test --project tests/MyApp.FunctionalTests/MyApp.FunctionalTests.csproj
dotnet test --filter "task=SW-1234"        # all unit + integration tests for a Jira Task
dotnet test --filter "requirement=SW-5678" # all functional / e2e tests for a Requirement
PLAYWRIGHT_TRACING=1 dotnet test --project tests/MyApp.FunctionalTests/MyApp.FunctionalTests.csproj
dotnet run --project tests/MyApp.Benchmarks --configuration Release -- --filter "*"
```

---

## Quick reference

| Aspect | Rule |
|---|---|
| Test runner | xUnit v3 on Microsoft Testing Platform — every tier |
| MTP opt-in | `global.json` with `"test": { "runner": "Microsoft.Testing.Platform" }` (required on .NET 10+) |
| xUnit v3 packages | `xunit.v3` + `xunit.analyzers` only — `xunit.v3.analyzers` does not exist; `xunit.v3.mtp-v2` conflicts with what `xunit.v3` already pulls in |
| Test csproj must-haves | `<ImplicitUsings>enable</ImplicitUsings>` + `<Nullable>enable</Nullable>` + `<OutputType>Exe</OutputType>` |
| Assertions | AwesomeAssertions. Never FluentAssertions v8+ (commercial license). |
| Mocking | NSubstitute |
| HTML parsing | AngleSharp (Razor / Blazor only) |
| `Program.cs` discoverability | Append `namespace MyApp.Web { public partial class Program { } }` (braced) |
| `WebApplicationFactory<T>` | Fully qualified — `WebApplicationFactory<MyApp.Web.Program>` |
| Project per tier | `*.UnitTests`, `*.IntegrationTests`, `*.FunctionalTests`, `*.Benchmarks` — never mixed |
| Test independence | Tests must run in parallel safely — no shared state, no order dependencies, each test owns its data |
| Test class naming | `{Subject}Tests` |
| Test method naming | `Method_Condition_Result` |
| Async cancellation | Pass `TestContext.Current.CancellationToken` to every async API that accepts one |
| Unit DB | `Microsoft.EntityFrameworkCore.InMemory` only for trivial handler tests; never for FK / unique / SQL-translation logic |
| Integration DB | **Testcontainers** with the production provider — never SQLite-in-memory as a stand-in |
| Endpoint coverage | Every API endpoint exercised at the integration tier with all scenarios — happy path, all auth-failure roles, validation, not-found, conflict, unauthenticated |
| `dotnet test` invocation | `--project <path>` — positional path is rejected by MTP |
| Functional tier | **Playwright** browser-based e2e, only for projects that serve a web UI; smoke per critical journey, not full coverage |
| Functional tier host | Kestrel on a random port; `WebApplicationFactory` does not work here |
| Selectors (Playwright) | `[data-testid]` only, never styling classes |
| Auth in integration tests | `TestAuthHandler` with role smuggled via test header — never a global bypass flag |
| DB cleanup between integration tests | Respawn (truncate user tables); never DROP/CREATE |
| Silent server errors | `FakeLoggerProvider` + teardown asserting no `Warning+` logs |
| Razor — broken `asp-action` / `asp-controller` | View-rendering test with AngleSharp `href` assertion |
| Razor — form binding bugs | Form round-trip test: render → harvest emitted `name` attrs → POST back → assert 302 + captured DTO; pin culture to invariant; `AllowAutoRedirect = false` |
| Benchmarks | BenchmarkDotNet, `[MemoryDiagnoser]`, dedicated runner, scheduled cadence |
| Docker for tests | Hosts dependencies, never the test runner; never benchmarks |
| Traceability | **Regulated projects only**, two levels: unit + integration tests use `[Trait(Traits.Task, "SW-XXXX")]` (Jira Task that introduced the behaviour); functional / e2e tests use `[Trait(Traits.Requirement, "SW-XXXX")]` (Jira Requirement the user-facing journey verifies). Infra/probe tests use `SW-INFRA` under `Traits.Task`. **Internal-only projects**: skip both traits. |
| Per-project files | `Usings.cs` (every project); `Traits.cs` only when the project uses trait keys |
| Test data | Builder helper or `Bogus` — never scattered hand-rolled literals |
| Formatting | `dotnet format --severity error` before staging |
