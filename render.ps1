# Render all pipeline notebooks in sequence
# Usage: .\render_all.ps1
# Working directory: project root (default in Positron)
$notebooks = @(
    "code/01_explore.qmd",
    "code/02_compile.qmd",
    "code/03_clean_w1.qmd",
    "code/04_clean_w2.qmd",
    "code/05_clean_w3.qmd",
    "code/06_stack.qmd",
    "code/07_recode.qmd"
)
$failed = $false
foreach ($notebook in $notebooks) {
    if (-not (Test-Path $notebook)) {
        Write-Host "⚠️  Skipping $notebook (not found)" -ForegroundColor Yellow
        continue
    }
    Write-Host "=== Rendering $notebook ===" -ForegroundColor Cyan
    quarto render $notebook
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        Write-Host "❌ FAILED: $notebook exited with code $exitCode" -ForegroundColor Red
        $failed = $true
        break
    }
    Write-Host ""
}
if ($failed) {
    Write-Host "Pipeline stopped due to failure." -ForegroundColor Red
    exit 1
}
else {
    Write-Host "✅ All notebooks rendered successfully." -ForegroundColor Green
    exit 0
}