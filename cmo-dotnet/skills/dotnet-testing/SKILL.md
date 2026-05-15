---
name: dotnet-testing
description: Testing standards for any C# / .NET project at C-Mo — Web API, Razor / MVC, Blazor, background services. Covers unit, integration, end-to-end, and performance tiers; xUnit + `WebApplicationFactory<Program>` + EF Core test DBs (SQLite-in-memory / Testcontainers); CQRS handler patterns; Razor view-rendering and form round-trip patterns when applicable. Use when writing, reviewing, or scaffolding tests; when wiring fixtures, mocks (RabbitMQ, S3, SMTP), or test CI. Pairs with `dotnet-conventions`.
---

# .NET Testing Standards

Tiered testing for any C-Mo .NET project — Web APIs, Razor / MVC sites, Blazor apps, background services. The skill is grounded in current practice in `cloud-backend-subsystems` (API-only) and extended with Razor-specific patterns for projects that render views. Sections that only apply to one project type are marked.

Load this skill whenever writing tests, scaffolding test projects, adding test dependencies, designing test CI, or reviewing a PR that touches `tests/`.

The full pyramid:

| Tier | Project suffix | Scope | Stack (target) |
|---|---|---|---|
| Unit | `*.Tests` (Unit-style classes) | Pure logic — handlers, validators, services, helpers. No host, no I/O. EF only via `InMemory`. | xUnit v3 + AwesomeAssertions + NSubstitute |
| Integration | `*.Tests` (Integration-style classes) | Real ASP.NET Core pipeline in-process via `WebApplicationFactory<Program>`. Real DB (SQLite-in-memory **or** Testcontainers PostgreSQL). Catches policy/auth, validators, model binding, MediatR pipeline, EF migrations. | xUnit v3 + `Microsoft.AspNetCore.Mvc.Testing` + Testcontainers (target) or `Microsoft.Data.Sqlite` (transitional) |
| Functional / e2e | external compose | Real running stack via `docker-compose.e2e.yml` (`make deploy-e2e`). Cross-service flows, RabbitMQ events, MinIO, mailpit. | Driven from outside .NET; no in-repo runner yet |
| Performance | `*.Benchmarks` | Micro-benchmarks of hot paths. Add only when a hot path is identified. | BenchmarkDotNet console app |

C-Mo currently keeps unit and integration tests in a single `*.Tests` project per src project (e.g. `CmoCloudBackend.AnnotationsAPI.Tests`). That stays the norm — do **not** split into `*.UnitTests` / `*.IntegrationTests` unless the project's test wall-clock or CI cadence forces it. Use class-level naming (`*HandlerTest` vs `*IntegrationTest`) and traits to distinguish tiers within the same project.

Always start with a handler-level unit test for new MediatR logic, add an integration test the moment auth/policy, validators, or DB constraints are involved, and add a benchmark only when a hot path is identified.

---

## Hard rules (apply to every test, every project)

- **Requirements traceability — required for regulated projects, optional for internal-only projects.**
  - **Required**: medical-device software, customer-facing backends, anything under an IEC 62304 / regulatory audit trail (e.g. `cloud-backend-subsystems`). Every test method carries a `[Trait(Traits.Requirement, "SW-XXXX")]` linking it to a **software requirement** — not a Jira task / sprint ticket. The `SW-XXXX` code is a requirement ID; where requirements live (Jira issues typed "Requirement", an IEC 62304 trace matrix, a separate spec) is a project decision. The trait lives next to `[Fact]` / `[Theory]`. Tests that don't map to a single requirement (route-sanity probes, log-assertion teardowns, infra smoke tests) use `[Trait(Traits.Requirement, "SW-INFRA")]` or another agreed sentinel — never omit the trait in regulated projects.
  - **Optional**: internal tools, developer tooling, throwaway experiments, build/CI helpers. Skip the trait entirely — don't fake requirement IDs to "look compliant". If the project might later become customer-facing, add traceability at that point (not before).
  - The project's top-level README or `CLAUDE.md` should state which mode applies. If it's silent and the project ships software that runs on a medical device or customer environment, **assume traceability is required**.
- **Every test project ships a `Usings.cs`** at the project root (see template below) with `global using Xunit;` and `global using Moq;` (or `global using NSubstitute;` for new projects). A `Traits.cs` ships **only** in projects that need traceability (see above) or that use other trait keys (`Category`, `Speed`, etc.).
- **Test class name = `{SubjectClass}Test`** (singular, matches C-Mo's repo convention — not `Tests`). Test method name = `Method_Condition_Result` (e.g. `Approve_PendingInvoice_SetsStatusApproved`).
- **Test files mirror the src folder structure**: `src/CmoCloudBackend.AnnotationsAPI/Features/AnnotationProject/Commands/CreateAnnotationProject/CreateAnnotationProjectCommandHandler.cs` → `tests/CmoCloudBackend.AnnotationsAPI.Tests/Features/AnnotationProject/Commands/CreateAnnotationProjectCommandHandlerTest.cs`.
- **Nullable reference types enabled** (`<Nullable>enable</Nullable>`) — same rule as production code. Use `string?` where AngleSharp / framework APIs return nullable; do not blanket-`!` framework returns.
- **`async`/`await` all the way down**. Pass a `CancellationToken` to every async API that accepts one — on xUnit v3, that's `TestContext.Current.CancellationToken`; on xUnit v2 use `CancellationToken.None` (do not invent a token source per test).
- **No `Thread.Sleep`, no arbitrary delays.** If a test is flaky on timing, the production code has a race. Fix the race, not the test.

---

## SDK & runner setup

### Target state — xUnit v3 on Microsoft Testing Platform

On **.NET 10 SDK and later**, `dotnet test` no longer falls back to VSTest. New projects (and projects migrating off xUnit v2) must opt in to MTP at the repo root:

```jsonc
// global.json
{
  "sdk": {
    "version": "10.0.101",
    "rollForward": "latestMajor",
    "allowPrerelease": false
  },
  "test": {
    "runner": "Microsoft.Testing.Platform"
  }
}
```

Without the `"test"` block, the MTP runner errors out with:
`error : Testing with VSTest target is no longer supported by Microsoft.Testing.Platform on .NET 10 SDK and later. If you use dotnet test, you should opt-in to the new dotnet test experience.`

`cloud-backend-subsystems` is currently on xUnit v2 + VSTest fallback. New repos start on v3 + MTP. When migrating an existing repo: bump every test csproj to `xunit.v3` + `xunit.analyzers`, drop `xunit.runner.visualstudio` and `XunitXml.TestLogger`, add the `"test"` block to `global.json`, and switch any positional `dotnet test <path>` to `dotnet test --project <path>` (MTP does not accept the positional form).

### Current xUnit v2 baseline (`cloud-backend-subsystems`)

Existing projects keep xUnit v2 until the next non-trivial test-infra touch. The current packages:

```xml
<PackageReference Include="xunit" Version="2.9.3" />
<PackageReference Include="xunit.runner.visualstudio" Version="3.1.5">
  <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
  <PrivateAssets>all</PrivateAssets>
</PackageReference>
<PackageReference Include="XunitXml.TestLogger" Version="8.0.0" />
<PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.4.0" />
<PackageReference Include="coverlet.collector" Version="8.0.1" />
```

### `Program.cs` discoverability for `WebApplicationFactory`

`WebApplicationFactory<TEntryPoint>` needs `TEntryPoint` to be a real class. .NET 10 templates use top-level statements, which puts the implicit `Program` class in the global namespace. Add this **at the end of `Program.cs`**, in a braced namespace:

```csharp
app.Run();

namespace CmoCloudBackend.AnnotationsAPI
{
    public partial class Program { }
}
```

File-scoped namespaces (`namespace X;`) **don't work** here — CS8956: a file-scoped namespace can't follow top-level statements. Use the braced form.

Tests then reference it as `WebApplicationFactory<Program>` — each `*.Tests` project references exactly one src project, so the short form is unambiguous. If a project ever adds a `*.Benchmarks` sibling with its own `Program`, switch to the fully-qualified form (`WebApplicationFactory<CmoCloudBackend.AnnotationsAPI.Program>`) in both.

### Test csproj boilerplate every project needs

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <ImplicitUsings>enable</ImplicitUsings>
    <Nullable>enable</Nullable>
    <LangVersion>13</LangVersion>
    <IsPackable>false</IsPackable>
    <!-- Required by Microsoft.AspNetCore.Mvc.Testing for static-asset manifests on .NET 10+ -->
    <PreserveCompilationContext>true</PreserveCompilationContext>
    <!-- On xUnit v3 / MTP, the test host is an executable: -->
    <!-- <OutputType>Exe</OutputType> -->
  </PropertyGroup>

  <!-- Package references — see tier-specific sections below -->

  <ItemGroup>
    <ProjectReference Include="..\..\src\CmoCloudBackend.AnnotationsAPI\CmoCloudBackend.AnnotationsAPI.csproj" />
  </ItemGroup>

</Project>
```

`<ImplicitUsings>` and `<Nullable>` are not on by default in test SDKs even though they're on in src — without them you get CS0246 on `Task`/`HttpClient` and lose NRT warnings.

---

## Shared per-project files

These files live at the test project root and apply to every test in the assembly.

### `Traits.cs` — trait keys *(only in projects that need traits)*

Ship this only when the project (a) requires requirements traceability or (b) uses other trait keys for filtering (`Category`, `Speed`, etc.). Internal-only projects without traceability can skip the file entirely.

```csharp
namespace CmoCloudBackend.AnnotationsAPI.Tests;

public static class Traits {
    public const string Requirement = "requirement";
    // Add other keys (Category, Speed, etc.) here — do not invent ad-hoc strings.
}
```

### `Usings.cs` — global usings *(every project)*

```csharp
// xUnit v2 baseline
global using Xunit;
global using Moq;

// xUnit v3 target (replace Moq line with NSubstitute when migrating)
// global using Xunit;
// global using NSubstitute;
```

Anything else (FluentAssertions / AwesomeAssertions, `Microsoft.EntityFrameworkCore`, etc.) goes in the test file itself — global usings are for things touched by nearly every test.

---

## Tier 1 — Unit Tests (handlers, validators, services, helpers)

Pure, fast, no I/O beyond `Microsoft.EntityFrameworkCore.InMemory` for handler tests that need a `DbContext`. Target: a few ms each.

### When InMemory is OK and when it isn't

`Microsoft.EntityFrameworkCore.InMemory`:

- ✅ Fast enough that handler tests stay sub-millisecond.
- ✅ Fine for testing handler logic that does `Add` / `SaveChanges` / simple `Where`.
- ❌ Does **not** enforce foreign keys, unique constraints, or any other relational invariant.
- ❌ Does **not** translate queries — uses LINQ-to-Objects. `string.Compare`, `ILIKE`, `JSON_VALUE`, raw SQL, anything provider-specific gives you a different result than prod (PostgreSQL).
- ❌ Does **not** run migrations.

Rule of thumb: **InMemory for handler-only unit tests where the queries are trivial**. The moment the test depends on FK enforcement, a unique index, a raw SQL expression, or a migration, promote to an **integration test** (SQLite-in-memory or Testcontainers).

### Stack

- **xUnit v3** (target) or xUnit v2 (current baseline) — same setup as the SDK section above.
- **`xunit.analyzers`** — catches swapped `Assert.Equal` args, missing `await` on async asserts, etc. (`xunit.v3.analyzers` does not exist — the same package serves v3.)
- **AwesomeAssertions** (target) for readable assertions. Apache-2.0 fork of FluentAssertions v7, drop-in API-compatible. Do **not** use FluentAssertions v8+ — Xceed commercial license. Current code uses `Assert.Equal` / `Assert.True` from xUnit, which is also fine; the rule is "no FluentAssertions v8+", not "must use AwesomeAssertions".
- **NSubstitute** (target) for new code, **Moq + MockQueryable.Moq** (current) for existing test projects. Don't mix the two within a single test class.
- **`Microsoft.EntityFrameworkCore.InMemory`** when a handler needs a `DbContext`.

### Csproj fragment (xUnit v2 baseline)

```xml
<ItemGroup>
  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.4.0" />
  <PackageReference Include="Microsoft.EntityFrameworkCore.InMemory" Version="10.0.5" />
  <PackageReference Include="MockQueryable.Moq" Version="10.0.5" />
  <PackageReference Include="Moq" Version="4.20.72" />
  <PackageReference Include="xunit" Version="2.9.3" />
  <PackageReference Include="xunit.runner.visualstudio" Version="3.1.5">
    <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    <PrivateAssets>all</PrivateAssets>
  </PackageReference>
  <PackageReference Include="coverlet.collector" Version="8.0.1">
    <IncludeAssets>runtime; build; native; contentfiles; analyzers; buildtransitive</IncludeAssets>
    <PrivateAssets>all</PrivateAssets>
  </PackageReference>
  <PackageReference Include="XunitXml.TestLogger" Version="8.0.0" />
</ItemGroup>
```

### Pattern — MediatR command handler with InMemory `DbContext`

```csharp
using CmoCloudBackend.AnnotationsAPI.Features.AnnotationProject.Commands.CreateAnnotationProject;
using CmoCloudBackend.DAL;
using MapsterMapper;
using Mapster;
using Microsoft.EntityFrameworkCore;

namespace CmoCloudBackend.AnnotationsAPI.Tests.Features.AnnotationProject.Commands;

public class CreateAnnotationProjectCommandHandlerTest {
    private static ApplicationDbContext NewContext() {
        var options = new DbContextOptionsBuilder<ApplicationDbContext>()
            .UseInMemoryDatabase($"annotations-{Guid.NewGuid()}")
            .Options;
        return new ApplicationDbContext(options);
    }

    private static Mapper NewMapper() => new(TypeAdapterConfig.GlobalSettings);

    [Fact]
    [Trait(Traits.Requirement, "SW-4821")]
    public async Task Handle_PersistsProjectWithProvidedWindow_AndReturnsItsId() {
        using var db = NewContext();
        var handler = new CreateAnnotationProjectCommandHandler(db, NewMapper());

        var command = new CreateAnnotationProjectCommand {
            MonitoringSessionId = Guid.NewGuid(),
            CreatedByUserId = Guid.NewGuid()
        };

        var id = await handler.Handle(command, CancellationToken.None);

        var stored = await db.AnnotationProjects.SingleAsync();
        Assert.Equal(id, stored.Id);
        Assert.Equal(command.MonitoringSessionId, stored.MonitoringSessionId);
    }
}
```

Each test gets a unique `InMemory` database name — never share a name across tests in the same class, or test order leaks state.

### Pattern — pure service with `Moq`

```csharp
public class S3ServiceTest {
    private readonly Mock<IAmazonS3> _amazonS3Client = new();
    private readonly S3Service _sut;

    public S3ServiceTest() {
        var settings = new S3ServiceSettings { BucketName = "cmo-tests", PreSignedTtlInMinutes = 10 };
        _sut = new S3Service(
            _amazonS3Client.Object,
            Mock.Of<IOptions<S3ServiceSettings>>(o => o.Value == settings),
            Mock.Of<ILogger<S3Service>>());
    }

    [Fact]
    [Trait(Traits.Requirement, "SW-806")]
    public async Task PutAsync_PutFileToS3() {
        // ... arrange a stream, act, assert + Verify the S3 client received the expected request
    }
}
```

### Pattern — `IQueryable` mock with `MockQueryable.Moq`

Use when a service depends on an `IQueryable<TEntity>` from a repo or `DbSet`-like abstraction. Without `MockQueryable.Moq`, async LINQ extensions throw `NotImplementedException`.

```csharp
var users = new List<User> { /* … */ }.BuildMock();
var dbContext = new Mock<ApplicationDbContext>();
dbContext.Setup(d => d.Users).Returns(users);
```

### Rules

- **One assertion concept per test.** Multiple `Assert.X` / `.Should()` calls are fine if they verify the same logical outcome.
- **`[Theory]` + `[InlineData]`** for parameterised tests. Never branch on input inside the test body.
- **No `WebApplicationFactory`, no `HttpClient`, no SQL container** in unit tests — that's the integration tier.
- **Pass `TestContext.Current.CancellationToken`** to async APIs on xUnit v3. The `xUnit1051` analyzer warns when you don't, and the warning becomes meaningful if a test hangs.

---

## Tier 2 — Integration Tests (the workhorse tier for C-Mo)

Runs the real ASP.NET Core pipeline in-process via `WebApplicationFactory<Program>`. This is where most of C-Mo's testing happens — catches broken policies, broken validators, broken routes, broken EF migrations, and broken MediatR pipeline wiring.

### Stack

- **xUnit v3** (target) or xUnit v2 (current).
- **`Microsoft.AspNetCore.Mvc.Testing`** — provides `WebApplicationFactory<TEntryPoint>` and `TestServer`.
- **Test database**:
  - **Target — Testcontainers PostgreSQL** for new projects. Highest fidelity with prod (real `pg_catalog`, real FK enforcement, real SQL translation, real migrations). One container per fixture, started in `IAsyncLifetime.InitializeAsync`, killed in `DisposeAsync`.
  - **Current — `Microsoft.Data.Sqlite` `DataSource=:memory:`** (in `cloud-backend-subsystems`). Faster than Testcontainers, no Docker required, but PostgreSQL-specific features (`jsonb`, snake-case-vs-double-quoted-identifiers, partial indexes) silently behave differently.
  - **Never** `Microsoft.EntityFrameworkCore.InMemory` for integration tests — see InMemory pitfalls above.
- **`Microsoft.Extensions.Diagnostics.Testing`** for `FakeLoggerProvider` — assert no `Warning+` logs leak from a successful request.
- **`Respawn`** (target, when on Testcontainers) for fast per-test DB cleanup. Skip on SQLite-in-memory — each fixture spins up its own connection anyway.
- **`AngleSharp`** *(Razor / MVC projects only)* for HTML parsing and CSS-selector assertions on rendered views. Prefer AngleSharp over HtmlAgilityPack.

### Csproj fragment (current SQLite-in-memory baseline)

```xml
<ItemGroup>
  <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" Version="10.0.5" />
  <PackageReference Include="Microsoft.NET.Test.Sdk" Version="18.4.0" />
  <PackageReference Include="Microsoft.EntityFrameworkCore.Sqlite" Version="10.0.5" />
  <PackageReference Include="Microsoft.Data.Sqlite" Version="10.0.5" />
  <PackageReference Include="MockQueryable.Moq" Version="10.0.5" />
  <PackageReference Include="Moq" Version="4.20.72" />
  <PackageReference Include="xunit" Version="2.9.3" />
  <!-- xunit.runner.visualstudio, coverlet.collector, XunitXml.TestLogger as in Tier 1 -->
</ItemGroup>
```

For Testcontainers add `<PackageReference Include="Testcontainers.PostgreSql" />` and drop the two Sqlite packages.

### Pattern — `BaseIntegrationTest` (consolidate; do not copy-paste)

C-Mo's repo currently has the same `WithWebHostBuilder` / `ConfigureTestServices` / SQLite setup duplicated across `BaseIntegrationTest`, `BasicIntegrationTest`, `CreateAnnotationProjectIntegrationTest`, and more. Every new integration test should extend a **single** `BaseIntegrationTest` per project. The template below covers the common case; specialise via override / virtual hook only when a test genuinely needs different wiring.

```csharp
using System.Data.Common;
using System.Security.Claims;
using CmoCloudBackend.DAL;
using CmoCloudBackend.DAL.Models.Authentication;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.AspNetCore.TestHost;
using Microsoft.Data.Sqlite;
using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Diagnostics;
using Microsoft.EntityFrameworkCore.Infrastructure;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using RabbitMQ.Client;

namespace CmoCloudBackend.AnnotationsAPI.Tests;

public abstract class BaseIntegrationTest : IClassFixture<WebApplicationFactory<Program>> {
    private readonly WebApplicationFactory<Program> _factory;

    /// <summary>
    /// The factory built by the last call to <see cref="CreateClient"/>.
    /// Tests resolve scoped services (e.g. <c>ApplicationDbContext</c>) from
    /// this factory to seed data shared with the HTTP pipeline — the SQLite
    /// connection is registered as a singleton, so both sides see the same DB.
    /// </summary>
    protected WebApplicationFactory<Program> Factory { get; private set; } = null!;

    protected BaseIntegrationTest(WebApplicationFactory<Program> factory) {
        _factory = factory;
    }

    protected HttpClient CreateClient(string role, string? institutionId, bool validLicense = true) =>
        CreateAuthenticatedClient(role, institutionId, validLicense).Client;

    protected (HttpClient Client, WebApplicationFactory<Program> Factory) CreateAuthenticatedClient(
        string role, string? institutionId, bool validLicense = true, Guid? userId = null) {
        var factory = _factory.WithWebHostBuilder(builder => {
            builder.ConfigureTestServices(services => {
                ReplaceDatabaseWithSqlite(services);
                ReplaceRabbitMqWithMock(services);
                AddTestAuth(services, role, institutionId, validLicense, userId);
            });
            builder.UseEnvironment("Testing");
        });

        using var scope = factory.Services.CreateScope();
        scope.ServiceProvider.GetRequiredService<ApplicationDbContext>().Database.Migrate();

        Factory = factory;
        return (factory.CreateDefaultClient(), factory);
    }

    private static void ReplaceDatabaseWithSqlite(IServiceCollection services) {
        services.RemoveAll<IDbContextOptionsConfiguration<ApplicationDbContext>>();
        services.AddSingleton<DbConnection>(_ => {
            var connection = new SqliteConnection("DataSource=:memory:");
            connection.Open();
            return connection;
        });
        services.AddDbContext<ApplicationDbContext>((container, options) => {
            var connection = container.GetRequiredService<DbConnection>();
            options.UseSqlite(connection).UseSnakeCaseNamingConvention();
            options.ConfigureWarnings(w => w.Ignore(RelationalEventId.PendingModelChangesWarning));
        });
    }

    private static void ReplaceRabbitMqWithMock(IServiceCollection services) {
        services.AddSingleton<IConnectionFactory>(_ => {
            var connection = new Mock<IConnection>();
            connection.Setup(c => c.CreateChannelAsync(It.IsAny<CreateChannelOptions>(), It.IsAny<CancellationToken>()))
                .Returns(Task.FromResult(Mock.Of<IChannel>()));
            var factory = new Mock<IConnectionFactory>();
            factory.Setup(f => f.CreateConnectionAsync(It.IsAny<CancellationToken>()))
                .Returns(Task.FromResult(connection.Object));
            return factory.Object;
        });
    }

    private static void AddTestAuth(
        IServiceCollection services, string role, string? institutionId, bool validLicense, Guid? userId) {
        services.AddAuthentication(defaultScheme: "TestScheme")
            .AddScheme<AuthenticationSchemeOptions, TestAuthHandler>("TestScheme", options => {
                var claims = new List<Claim> { new(ClaimTypes.Role, role) };
                if (institutionId != null) claims.Add(new(UserClaim.CLAIM_INSTITUTION_ID, institutionId));
                claims.Add(new(ClaimTypes.NameIdentifier, (userId ?? Guid.NewGuid()).ToString()));
                claims.Add(new(UserClaim.CLAIM_LICENSE_EXPIRATION_DATE,
                    validLicense ? "2529161570" : "1642870370"));
                // Smuggle claims through `Events` so the handler can read them per request.
                // It's an awkward channel but avoids extra DI plumbing.
                options.Events = claims;
            });
    }
}
```

### Pattern — `TestAuthHandler`

Lives once per test project (not per test file). Reads the claim list smuggled through `AuthenticationSchemeOptions.Events`.

```csharp
public class TestAuthHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options,
    ILoggerFactory logger,
    UrlEncoder encoder)
    : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder) {

    private readonly List<Claim> _claims = (options.Get("TestScheme").Events as List<Claim>)!;

    protected override Task<AuthenticateResult> HandleAuthenticateAsync() {
        var identity = new ClaimsIdentity(_claims, "Test");
        var ticket = new AuthenticationTicket(new ClaimsPrincipal(identity), "TestScheme");
        return Task.FromResult(AuthenticateResult.Success(ticket));
    }
}
```

### Pattern — JSON API integration test (Web API projects)

```csharp
public class CreateAnnotationProjectIntegrationTest : BaseIntegrationTest {
    public CreateAnnotationProjectIntegrationTest(WebApplicationFactory<Program> factory) : base(factory) { }

    [Fact]
    [Trait(Traits.Requirement, "SW-4821")]
    public async Task Create_AsAnnotatorsManager_ReturnsCreated() {
        var callerId = Guid.NewGuid();
        var (client, factory) = CreateAuthenticatedClient(Role.AnnotatorsManager, institutionId: null, userId: callerId);

        using var scope = factory.Services.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
        var sessionId = await SeedMonitoringSessionAsync(db, callerId);

        var body = JsonContent.Create(new CreateAnnotationProjectCommand {
            MonitoringSessionId = sessionId,
            Name = "Integration Test Project",
        });

        var response = await client.PostAsync("/api/v1/projects", body);

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var id = await response.Content.ReadFromJsonAsync<Guid>();
        Assert.NotEqual(Guid.Empty, id);

        var stored = await db.AnnotationProjects.SingleAsync(p => p.Id == id);
        Assert.Equal(sessionId, stored.MonitoringSessionId);
    }

    [Theory]
    [InlineData(Role.InstitutionUser)]
    [InlineData(Role.InstitutionAdmin)]
    [InlineData(Role.DataAnnotator)]
    [Trait(Traits.Requirement, "SW-4821")]
    public async Task Create_WithNonManagerRole_ReturnsForbidden(string callerRole) {
        var (client, _) = CreateAuthenticatedClient(callerRole, institutionId: null);
        var body = JsonContent.Create(new CreateAnnotationProjectCommand { MonitoringSessionId = Guid.NewGuid() });

        var response = await client.PostAsync("/api/v1/projects", body);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }
}
```

### Razor / MVC patterns *(skip for Web-API-only projects)*

For projects that render server-side views, integration tests get a much sharper edge: tag helpers (`asp-action`, `asp-controller`, `asp-for`) **silently render the wrong (or empty) output** when broken, so you only learn about it when a user clicks a dead link or submits a form that doesn't bind. The view-rendering and form round-trip tests below catch those failures at PR time.

#### Pattern — view rendering with AngleSharp (catches broken `asp-action` / `asp-controller`)

```csharp
public class InvoicesViewTests : BaseIntegrationTest {
    public InvoicesViewTests(WebApplicationFactory<Program> factory) : base(factory) { }

    [Fact]
    [Trait(Traits.Requirement, "SW-XXXX")]
    public async Task Index_RendersDetailsLink_WithResolvedRoute() {
        var client = CreateClient(Role.InstitutionUser, institutionId: null);

        var response = await client.GetAsync("/Invoices");
        response.EnsureSuccessStatusCode();

        var html = await response.Content.ReadAsStringAsync();
        var document = await BrowsingContext.New(Configuration.Default)
            .OpenAsync(req => req.Content(html));

        var link = document.QuerySelector("a.invoice-details-link");

        Assert.NotNull(link);
        // Asserting on the resolved href catches typos in asp-action / asp-controller:
        // a broken tag helper renders href="" instead of throwing.
        Assert.StartsWith("/Invoices/Details/", link!.GetAttribute("href"));
    }
}
```

#### Pattern — `asp-for` probe (catches misnamed form bindings)

Strongly-typed views (`@model SomeDto`) get **build-time** validation — Razor compiles the view and `asp-for="NotARealProperty"` becomes `CS1061` at build, so the runtime probe is partially redundant. It still has value for:
- Weakly-typed views without a declared `@model`.
- Dynamic property access via `HtmlHelper` (`Html.NameFor`, `ViewData`-driven forms).
- Setups where Razor compile-on-build is disabled (some `Directory.Build.props` toggles).
- Catching the case where a model property is deleted and a stale build cache hides the failure locally.

```csharp
[Theory]
[InlineData("/Invoices/Create")]
[InlineData("/Users/Edit/1")]
[Trait(Traits.Requirement, "SW-XXXX")]
public async Task FormInputs_AllHaveNameAttributes(string url) {
    var client = CreateClient(Role.InstitutionAdmin, institutionId: null);

    var response = await client.GetAsync(url);
    response.EnsureSuccessStatusCode();

    var document = await BrowsingContext.New(Configuration.Default)
        .OpenAsync(req => req.Content(await response.Content.ReadAsStringAsync()));

    var unnamed = document.QuerySelectorAll("form :is(input, select, textarea)")
        .Where(e => string.IsNullOrEmpty(e.GetAttribute("name")))
        .Where(e => e.GetAttribute("type") != "submit" && e.GetAttribute("type") != "button")
        .ToList();

    Assert.True(unnamed.Count == 0,
        "every form input bound via asp-for must produce a name attribute");
}
```

#### Pattern — form round-trip test (catches binding-prefix and source-attribute bugs)

The view-rendering test catches broken `asp-action` links. This one catches broken **form submissions** — three real bugs at once:

1. **Prefix mismatch.** `<input asp-for="@abc.Property" />` renders as `name="abc.Property"`. The model binder uses the action's *parameter name* as the prefix, so `Create(InvoiceForm form)` looks for `form.Property` — fields starting with `abc.` are ignored, the DTO comes back default. Renaming the action parameter silently breaks the form.
2. **Wrong binding source.** `Create([FromQuery] InvoiceForm payload)` expects query-string values; form-encoded POST data won't bind. Same for `[FromBody]` (expects JSON), `[FromRoute]`, etc.
3. **Culture-sensitive parsing.** ASP.NET Core model binding parses decimals and dates with the request's `CurrentCulture`, not invariant — `"42.50"` binds to `0m` on a machine where the system culture is `pt-PT` (comma decimal). Pin the culture in the fixture or tests pass on one machine and fail on another.

The test renders the form, harvests every `name` attribute the renderer actually emitted, POSTs those exact names back, and asserts the action's parameter was populated. Strong signals at three layers:

- **Black-box**: `RedirectToAction` returns 302; a validation re-render returns 200. The status code alone tells you whether binding + validation succeeded.
- **White-box**: a test-only `IActionFilter` captures `context.ActionArguments` by correlation-id header, so the test can assert on the exact bound values regardless of what the action does next.
- **Diagnostic**: when the test fails, the message distinguishes *prefix mismatch* (DTO empty), *wrong source* (DTO empty), *culture* (string fields bound, numbers didn't), and *validation* (everything bound but failed a `[Required]`).

```csharp
// CapturedBindingFilter.cs — test-only, lives in the test project
public class CapturedBindings {
    public ConcurrentDictionary<string, IDictionary<string, object?>> ByCorrelationId { get; } = new();
}

public class CapturedBindingFilter : IActionFilter {
    public const string HeaderName = "X-Test-CorrelationId";
    private readonly CapturedBindings _store;
    public CapturedBindingFilter(CapturedBindings store) => _store = store;

    public void OnActionExecuting(ActionExecutingContext context) {
        if (!context.HttpContext.Request.Headers.TryGetValue(HeaderName, out var id) || string.IsNullOrEmpty(id)) {
            return;
        }
        _store.ByCorrelationId[id!] = new Dictionary<string, object?>(context.ActionArguments);
    }

    public void OnActionExecuted(ActionExecutedContext context) { }
}
```

Wire `CapturedBindings` + `CapturedBindingFilter` in your Razor-specific base class (alongside `ReplaceDatabaseWithSqlite` / `ReplaceRabbitMqWithMock`), and **pin the culture** to invariant:

```csharp
private static void ConfigureForRazorFormTests(IServiceCollection services, CapturedBindings store) {
    // Model binding for decimals/dates uses thread CurrentCulture, not invariant.
    // Pin it so tests behave the same on every dev machine and CI runner.
    CultureInfo.DefaultThreadCurrentCulture = CultureInfo.InvariantCulture;
    CultureInfo.DefaultThreadCurrentUICulture = CultureInfo.InvariantCulture;

    services.AddSingleton(store);
    services.AddSingleton<CapturedBindingFilter>();
    services.Configure<MvcOptions>(o => o.Filters.AddService<CapturedBindingFilter>());
}
```

The test:

```csharp
[Fact]
[Trait(Traits.Requirement, "SW-XXXX")]
public async Task Create_FormRoundTrip_BindsAllRenderedInputsToController() {
    var correlationId = Guid.NewGuid().ToString();
    var client = CreateClient(Role.InstitutionAdmin, institutionId: null);
    // Important: do NOT auto-follow redirects — without this, the client follows the 302 and you see
    // the redirected page's 200, masking the success signal.
    client.DefaultRequestHeaders.Add("X-Test-CorrelationId", correlationId);

    // 1. GET the rendered form
    var getResp = await client.GetAsync("/Invoices/Create");
    getResp.EnsureSuccessStatusCode();
    var document = await BrowsingContext.New(Configuration.Default)
        .OpenAsync(req => req.Content(await getResp.Content.ReadAsStringAsync()));
    var form = (IHtmlFormElement)document.QuerySelector("form")!;

    // 2. Harvest every name attribute the RENDERER produced — not what we expect.
    var sample = new Dictionary<string, string> { ["Number"] = "INV-001", ["Amount"] = "42.50" };
    var fields = new Dictionary<string, string>();
    foreach (var el in form.QuerySelectorAll("input[name], select[name], textarea[name]")) {
        if (el.GetAttribute("type") is "submit" or "button") continue;
        var name = el.GetAttribute("name")!;
        var leaf = name.Contains('.') ? name[(name.LastIndexOf('.') + 1)..] : name;
        fields[name] = sample.TryGetValue(leaf, out var v) ? v : "x";
    }

    // 3. POST back to the form's action URL with the harvested names
    var action = form.GetAttribute("action");
    if (string.IsNullOrEmpty(action)) action = getResp.RequestMessage!.RequestUri!.PathAndQuery;
    var postResp = await client.PostAsync(action, new FormUrlEncodedContent(fields));

    // 4. Black-box: 302 = success, 200 = validation re-render = something didn't bind
    // 5. White-box: address the bound DTO by *type*, not by parameter name. That makes the test
    //    resilient to parameter renames while still failing if no field-name prefix matches.
    var captured = Captured.ByCorrelationId.GetValueOrDefault(correlationId);
    var bound = captured?.Values.OfType<InvoiceForm>().FirstOrDefault();
    var diagnostic = captured is null
        ? "filter never ran — antiforgery or pipeline blocked the POST"
        : bound is null
            ? $"action ran but no InvoiceForm in args. Args: [{string.Join(",", captured.Keys)}] — prefix mismatch?"
            : $"DTO bound: Number='{bound.Number}' Amount={bound.Amount} — validation failed or culture parse failed";

    Assert.True(postResp.StatusCode == HttpStatusCode.Redirect, diagnostic);
    Assert.NotNull(bound);
    Assert.Equal("INV-001", bound!.Number);
    Assert.Equal(42.50m, bound.Amount);
}
```

Key design choices, validated end-to-end:

- **Address the bound DTO by *type*, not by parameter name** (`args.Values.OfType<InvoiceForm>().FirstOrDefault()`) — resilient to parameter renames while still failing if no field-name prefix matches.
- **`AllowAutoRedirect = false` is mandatory** on the `HttpClient` — without it, the client follows the 302 and the success signal is masked. Build the client via `factory.CreateClient(new() { AllowAutoRedirect = false })` for these tests (override the base helper or build inline).
- **`CultureInfo.DefaultThreadCurrentCulture` in the host wiring is the only reliable culture pin.** `Accept-Language: en-US` from the client does nothing unless the app uses `UseRequestLocalization`, which the default template doesn't.
- **Register the filter as a service** via `o.Filters.AddService<T>()` (not `o.Filters.Add<T>()`) — otherwise it gets a fresh instance per request and the singleton `CapturedBindings` store wouldn't be reachable.

### Pattern — partial-graph seeding with `PRAGMA foreign_keys = OFF`

When a handler reads only a few entities but the entity graph has dozens of foreign-key parents you don't care about, disable FK enforcement on the SQLite connection so the seed call can skip the irrelevant parents:

```csharp
services.AddSingleton<DbConnection>(_ => {
    var connection = new SqliteConnection("DataSource=:memory:");
    connection.Open();
    using var cmd = connection.CreateCommand();
    cmd.CommandText = "PRAGMA foreign_keys = OFF;";
    cmd.ExecuteNonQuery();
    return connection;
});

// After Migrate(), re-apply (Migrate re-enables foreign_keys by default):
db.Database.Migrate();
db.Database.ExecuteSqlRaw("PRAGMA foreign_keys = OFF;");
```

This **only** belongs in tests that seed a minimal slice. If you find yourself toggling FK enforcement to make a test pass against a real FK violation, the test is hiding a real bug — fix the seed, not the constraint.

### Pattern — route-sanity probe (catches dead routes statically)

A single test that walks every action descriptor and asks `LinkGenerator` to resolve a URL. Cheap, no HTTP. Catches `[Route]` attributes that drift from MediatR command paths during refactors (in APIs) and dead controller/action pairs referenced by tag helpers (in Razor / MVC projects, complementing the view-rendering test above).

```csharp
public class RouteSanityTests : BaseIntegrationTest {
    public RouteSanityTests(WebApplicationFactory<Program> factory) : base(factory) { }

    [Fact]
    [Trait(Traits.Requirement, "SW-INFRA")]
    public void AllActionDescriptors_ResolveToAUrl() {
        // Force the factory to materialise without auth/db wiring concerns.
        var (_, factory) = CreateAuthenticatedClient(Role.InstitutionAdmin, institutionId: null);

        using var scope = factory.Services.CreateScope();
        var provider = scope.ServiceProvider.GetRequiredService<IActionDescriptorCollectionProvider>();
        var links = scope.ServiceProvider.GetRequiredService<LinkGenerator>();

        foreach (var d in provider.ActionDescriptors.Items.OfType<ControllerActionDescriptor>()) {
            var url = links.GetPathByAction(action: d.ActionName, controller: d.ControllerName);
            Assert.False(string.IsNullOrEmpty(url),
                $"{d.ControllerName}.{d.ActionName} has no resolvable route");
        }
    }
}
```

### Pattern — log-assertion teardown (no silent server errors)

Add a `Warning+`-log assertion to the base class. If the integration test passes but the request logged a `Warning` or worse, fail the test in `Dispose`. Lifted from OrchardCore.

```csharp
public abstract class IntegrationTestBase : BaseIntegrationTest, IDisposable {
    private readonly FakeLogCollector _logs;

    protected IntegrationTestBase(WebApplicationFactory<Program> factory) : base(factory) {
        _logs = Factory.Services.GetRequiredService<FakeLogCollector>();
        _logs.Clear();
    }

    public void Dispose() {
        var bad = _logs.GetSnapshot().Where(r => r.Level >= LogLevel.Warning).ToList();
        Assert.True(bad.Count == 0, $"Request logged {bad.Count} warning(s)/error(s)");
    }
}
```

Register `services.AddLogging(b => b.AddFakeLogging())` inside `ReplaceDatabaseWithSqlite`-style helpers when adopting this.

### Rules

- **Use `IClassFixture<WebApplicationFactory<Program>>` once, in the base class.** Do not new a factory per test — it re-builds the host every time and is expensive.
- **One DB per fixture call (SQLite-in-memory) or one container per fixture (Testcontainers).** Do not share containers across test classes that run in parallel — Testcontainers + xUnit collection parallelism causes port collisions and FK race conditions.
- **JSON serialiser default: PascalCase in C#, camelCase on the wire.** Same rule as production code. Assert against camelCase JSON paths when poking into `JsonNode`/`JsonDocument`.
- **Test code may use `string?` and friends** where AngleSharp / framework APIs return nullable. This is the only exception to the project-wide "annotate everything explicitly" rule.
- **Never bypass auth with a global flag.** Always go through `TestAuthHandler` — that's how you exercise the real authorization pipeline.
- **URL assertions are the one place** the "no hardcoded URLs" rule from `dotnet-conventions` is relaxed — you're asserting against the rendered URL, not constructing one.

---

## Tier 3 — Functional / End-to-End

C-Mo's e2e tests today live **outside** the .NET test runner — `make deploy-e2e` boots the full stack via `docker-compose.e2e.yml` (Authenticator, Management, Medical, Annotations, BackgroundServices, MinIO, mailpit, RabbitMQ, Postgres) and a separate harness exercises real flows.

There is currently **no in-repo Playwright project** for browser-driven e2e. If/when one is added:

- New csproj `*.FunctionalTests` separate from `*.Tests` — different runtime cost, different CI cadence.
- **`Microsoft.Playwright`** .NET binding + xUnit v3.
- **Real Kestrel host on a random port** — *not* `WebApplicationFactory<Program>` (TestServer is in-memory; Playwright needs a real listener).
- Browser install via `pwsh playwright.ps1 install chromium` or `Microsoft.Playwright.Program.Main(["install", "chromium"])` from the fixture (idempotent). `dotnet exec ... Microsoft.Playwright.dll install` does **not** work — no `runtimeconfig.json` on the DLL.
- Selectors: `[data-testid="..."]` only. Never CSS classes that exist for styling.
- Enable Playwright tracing via env var `PLAYWRIGHT_TRACING=1`; upload traces as CI artifacts on failure.

Until the in-repo Playwright tier exists, treat the docker-compose flow as the functional tier and don't try to fold it into the unit/integration projects.

---

## Tier 4 — Performance / Benchmarks

Add only when a hot path is identified — never as table-stakes for a new project.

- New csproj `*.Benchmarks`, `<OutputType>Exe</OutputType>`, `<IsTestProject>false</IsTestProject>`, `<ServerGarbageCollection>true</ServerGarbageCollection>`.
- **`BenchmarkDotNet`**; `BenchmarkSwitcher.FromAssembly(typeof(Program).Assembly).Run(args);` as `Main`.
- Always include `[MemoryDiagnoser]`. Allocation regressions matter as much as time regressions.
- For before/after of a refactor: keep both implementations, mark the old `[Benchmark(Baseline = true)]` and the new `[Benchmark]` — BenchmarkDotNet prints the ratio.
- **Never run benchmarks in Docker or on shared CI runners.** You need a stable CPU and scheduler. Dedicated machine, nightly cadence, results posted to a tracking issue.
- If the benchmark project defines its own `static class Program`, switch the integration tests to fully-qualified `WebApplicationFactory<CmoCloudBackend.AnnotationsAPI.Program>` to disambiguate.

---

## Docker / Testcontainers policy

Docker hosts **the dependencies the tests need**, not the test runner.

- **Unit** — no Docker. No I/O.
- **Integration** — `Testcontainers.PostgreSql` (target) per fixture, started in `IAsyncLifetime`. `Testcontainers.RabbitMq` / `Testcontainers.Minio` when the test exercises real broker / object-store flows; mock the connection factory otherwise.
- **Functional / e2e** — full stack via `docker-compose.e2e.yml` for now.
- **Benchmarks** — never in Docker.

Avoid `docker-compose up` for integration tests — it introduces shared state across runs and breaks Testcontainers' per-fixture isolation.

---

## CI layout

Run each tier on its own cadence:

| Workflow | Tier | When |
|---|---|---|
| `tests.yml` | Unit + Integration | Every push (PR + main) |
| `e2e.yml` | Functional | Every PR (after build), main, scheduled nightly |
| `benchmarks.yml` | Benchmarks | Nightly on a dedicated runner |

Filter tests via `dotnet test --filter` on traits, project, or class — never by test name patterns.

```bash
# Unit-only (run handler/service tests, skip integration)
dotnet test --filter "Category=Unit"

# All tests for a single requirement
dotnet test --filter "requirement=SW-4821"

# Specific class
dotnet test --filter "FullyQualifiedName~CreateAnnotationProjectIntegrationTest"

# Full solution
dotnet test --configuration Release
```

When migrating to xUnit v3 / MTP, switch positional paths to `--project`:

```bash
# v3 / MTP
dotnet test --project tests/CmoCloudBackend.AnnotationsAPI.Tests/CmoCloudBackend.AnnotationsAPI.Tests.csproj
```

---

## Formatting

- Run `dotnet format --severity error` on every new or modified test file before staging (same gate as production code in `cloud-backend-subsystems`).
- A local pre-commit hook that runs on staged files only is not authoritative — `dotnet format --verify-no-changes --severity error` runs against the whole tree in CI and may flag different formatting in tree-context. Run the formatter yourself.

---

## Quick reference

| Aspect | Rule |
|---|---|
| Test runner (target) | xUnit v3 on Microsoft Testing Platform |
| Test runner (current) | xUnit v2 + `xunit.runner.visualstudio` + `XunitXml.TestLogger` (no migration until non-trivial test-infra change) |
| MTP opt-in | `global.json` at repo root with `"test": { "runner": "Microsoft.Testing.Platform" }` (required on .NET 10+) |
| Test csproj must-haves | `<ImplicitUsings>enable</ImplicitUsings>` + `<Nullable>enable</Nullable>` + `<PreserveCompilationContext>true</PreserveCompilationContext>` |
| Assertions | xUnit `Assert.X` (current) or AwesomeAssertions (target). Never FluentAssertions v8+ (commercial). |
| Mocking | Moq + MockQueryable.Moq (current) or NSubstitute (target, new projects) |
| Traceability | **Regulated projects only** (medical-device software, customer-facing backends): every test method has `[Trait(Traits.Requirement, "SW-XXXX")]` linking to a **software requirement** (not a Jira task). Infra/probe tests use `SW-INFRA` or another agreed sentinel. **Internal-only projects**: skip the trait — don't fake IDs to look compliant. |
| Per-project files | `Usings.cs` at the test project root (every project); `Traits.cs` only when the project uses traits (traceability or filtering) |
| `Program.cs` discoverability | Append `namespace X { public partial class Program { } }` (braced) — file-scoped doesn't work after top-level statements |
| `WebApplicationFactory<T>` | Short `WebApplicationFactory<Program>` is fine until a benchmark sibling adds its own `Program`; then fully-qualify |
| Test class naming | `{Subject}Test` (singular, matches the repo) |
| Test method naming | `Method_Condition_Result` |
| Folder mirroring | tests/...path mirrors src/...path exactly |
| Async cancellation | Pass `TestContext.Current.CancellationToken` (xUnit v3) / `CancellationToken.None` (xUnit v2) to async APIs |
| Unit DB | `Microsoft.EntityFrameworkCore.InMemory` only for trivial handler tests; never for FK / unique / SQL-translation logic |
| Integration DB (current) | `Microsoft.Data.Sqlite` `DataSource=:memory:` + `UseSqlite(...).UseSnakeCaseNamingConvention()` |
| Integration DB (target) | `Testcontainers.PostgreSql` per fixture |
| `WebApplicationFactory` fixture | Consolidated `BaseIntegrationTest` per project — do **not** duplicate `WithWebHostBuilder` blocks across test files |
| Test auth | `TestAuthHandler` + claims smuggled through `AuthenticationSchemeOptions.Events` |
| RabbitMQ in tests | Mock `IConnectionFactory` in the integration base class; real broker only in e2e |
| Partial-graph seeding | `PRAGMA foreign_keys = OFF` on the SQLite connection (after `Migrate`) — only for tests that intentionally skip parents |
| Silent server errors | `FakeLoggerProvider` + teardown asserting no `Warning+` logs |
| Route drift | `LinkGenerator` route-sanity probe over `ActionDescriptors` (APIs + Razor) |
| Razor — broken `asp-action` / `asp-controller` | View-rendering test + AngleSharp assertion on resolved `href` |
| Razor — broken `asp-for` | Probe verifying every form input has a non-empty `name` attribute (paired with strongly-typed `@model` compile-time checks) |
| Razor — form binding (prefix mismatch / wrong `[FromX]` / culture parse) | Form round-trip test: render → harvest emitted `name` attrs → POST back → assert 302 + captured DTO via test-only `IActionFilter` |
| Razor — culture pin | `CultureInfo.DefaultThreadCurrentCulture = CultureInfo.InvariantCulture` in the host wiring — ASP.NET model binding uses thread culture, not invariant |
| Razor — `HttpClient` | `AllowAutoRedirect = false` for form round-trip tests; without it the 302 is followed and the success signal is masked |
| Functional / e2e | `make deploy-e2e` for now; future Playwright project on real Kestrel |
| Benchmarks | BenchmarkDotNet, `[MemoryDiagnoser]`, dedicated runner, nightly |
| Docker for tests | Hosts dependencies, never hosts the test runner; never benchmarks |
| Selectors (future Playwright) | `[data-testid]`, never styling classes |
| Formatting | `dotnet format --severity error` before staging; CI gates on `--verify-no-changes` |
