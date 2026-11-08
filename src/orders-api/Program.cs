var builder = WebApplication.CreateBuilder(args);
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
