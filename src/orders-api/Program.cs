var builder = WebApplication.CreateBuilder(args);
if (Environment.GetEnvironmentVariable("CRASH_ON_START") == "true")
{
    throw new InvalidOperationException("Crash drill: CRASH_ON_START is set");
}
builder.Services.AddOpenApi();

var app = builder.Build();

if (app.Environment.IsDevelopment())
{
    app.MapOpenApi();
}

// Liveness check: Docker, CI and Kubernetes call this
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

// Which environment am I in, and what config did I load?
app.MapGet("/api/info", (IConfiguration config, IWebHostEnvironment env) =>
    Results.Ok(new
    {
        environment = env.EnvironmentName,
        greeting = config["Greeting"] ?? "not set"
    }));

app.Run();
// drill 8.4
