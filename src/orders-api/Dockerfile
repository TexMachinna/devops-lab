# ---------- Stage 1: build ----------
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src

COPY OrdersApi.csproj .
RUN dotnet restore

COPY . .
RUN dotnet publish -c Release -o /app/publish --no-restore

# ---------- Stage 2: runtime ----------
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS final
WORKDIR /app
COPY --from=build /app/publish .
ARG GIT_SHA=unknown
LABEL org.opencontainer.image.revision=$GIT_SHA

USER $APP_UID
EXPOSE 8080
ENTRYPOINT ["dotnet", "OrdersApi.dll"]