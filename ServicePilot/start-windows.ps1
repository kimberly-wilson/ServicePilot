# Run from PowerShell: .\start-windows.ps1
param([switch]$TestChat)
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot

$docker = Get-Command docker -ErrorAction SilentlyContinue
if ($docker) {
    $dockerExe = $docker.Source
} else {
    $dockerExe = @(
        "$env:ProgramFiles\Docker\Docker\resources\bin\docker.exe",
        "$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin\docker.exe"
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}
if (-not $dockerExe) { throw 'Install Docker Desktop, then run this script again.' }
if (-not (Test-Path -LiteralPath '.env')) { throw 'Create .env using the configuration in the project guide.' }

function Invoke-Docker {
    & $dockerExe @args
    if ($LASTEXITCODE -ne 0) { throw "Docker command failed: $args" }
}

Write-Host '[1/5] Checking Docker engine and Compose configuration'
Invoke-Docker info --format '{{.ServerVersion}}'
Invoke-Docker compose config --quiet

Write-Host '[2/5] Starting Redis and ChromaDB'
Invoke-Docker compose up -d --wait --wait-timeout 180 redis chromadb

Write-Host '[3/5] Building and starting EchoMind'
Invoke-Docker compose up -d --build --wait --wait-timeout 300 echomind

Write-Host '[4/5] Starting Prometheus and Nginx'
Invoke-Docker compose up -d --wait --wait-timeout 120 prometheus nginx

Write-Host '[5/5] Checking HTTP endpoints'
foreach ($url in @(
    'http://localhost:8000/health',
    'http://localhost:8000/knowledge/stats',
    'http://localhost:8000/skills',
    'http://localhost/health',
    'http://localhost:9090/-/healthy'
)) {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
    Write-Host "$url -> HTTP $($response.StatusCode)"
}
if ($TestChat) {
    $body = @{
        message = 'Hello, please introduce yourself.'
        user_id = 'setup_check'
        conv_id = "setup_$([guid]::NewGuid().ToString('N'))"
    } | ConvertTo-Json
    Invoke-RestMethod -Method Post -Uri 'http://localhost:8000/chat' -ContentType 'application/json' -Body $body -TimeoutSec 180 | ConvertTo-Json -Depth 8
}
Invoke-Docker compose ps
Write-Host 'Swagger: http://localhost:8000/docs'
Write-Host 'Stop services: docker compose stop'
