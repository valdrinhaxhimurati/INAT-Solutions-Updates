param(
  [Parameter(Mandatory=$true)][string]$Version,                     # z.B. v1.0.0
  [string]$ExePath = "dist\INAT-Solutions.exe",                     # Pfad zu deiner gebauten EXE
  [string]$PublicRepo = "valdrinhaxhimurati/INAT-Solutions-Updates",
  [string]$Branch = "gh-pages",
  [string]$ExeName = "INAT-Solutions.exe",                         # Zielname auf Pages (kein Leerzeichen empfohlen)
  [string]$PublishToken = $env:PUBLISH_TOKEN                       # optional: PAT (public_repo)
)

try {
    Write-Host "Publish: Version $Version -> $PublicRepo (branch $Branch)"
    if (-not (Test-Path $ExePath)) { throw "Exe nicht gefunden: $ExePath" }

    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $work = Join-Path $scriptDir "out"
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
    New-Item -Path $work -ItemType Directory | Out-Null

    # kopiere exe nach out und benenne ggf. um
    $targetExe = Join-Path $work $ExeName
    Copy-Item -Path $ExePath -Destination $targetExe -Force

    # SHA256 berechnen
    $hash = Get-FileHash -Path $targetExe -Algorithm SHA256
    $sha = $hash.Hash.ToLower()
    Write-Host "SHA256: $sha"

    # erzeuge version.json
    $parts = $PublicRepo.Split('/')
    if ($parts.Length -lt 2) { throw "PublicRepo muss 'owner/repo' sein." }
    $owner = $parts[0]; $repo = $parts[1]
    $url = "https://$owner.github.io/$repo/$ExeName"
    $meta = @{ version = $Version; url = $url; sha256 = $sha }
    $meta | ConvertTo-Json -Depth 3 | Out-File -FilePath (Join-Path $work "version.json") -Encoding utf8

    # clone public repo gh-pages (oder erstelle Branch)
    $cloneUrl = if ($PublishToken) { "https://x-access-token:$PublishToken@github.com/$PublicRepo.git" } else { "https://github.com/$PublicRepo.git" }
    $pubdir = Join-Path $scriptDir "pubrepo"
    if (Test-Path $pubdir) { Remove-Item $pubdir -Recurse -Force }

    Write-Host "Cloning $PublicRepo (branch $Branch)..."
    $cl = git clone --single-branch --branch $Branch $cloneUrl $pubdir 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Branch $Branch existiert vermutlich nicht — erstelle $Branch..."
        git clone $cloneUrl $pubdir
        Push-Location $pubdir
        git checkout --orphan $Branch
        git rm -rf . 2>$null
        git commit --allow-empty -m "Create $Branch"
        git push origin $Branch
        Pop-Location
        Remove-Item -Recurse -Force $pubdir
        git clone --single-branch --branch $Branch $cloneUrl $pubdir
    }

    # copy files into pubrepo
    Write-Host "Kopiere Dateien nach pubrepo/ ..."
    Copy-Item -Path (Join-Path $work "*") -Destination $pubdir -Recurse -Force

    Push-Location $pubdir
    git config user.email "ci@github-actions"
    git config user.name "CI Publisher"
    git add -A
    git commit -m "Publish $Version" 2>$null || Write-Host "Keine Änderungen zu committen"
    git push origin $Branch
    Pop-Location

    # cleanup
    Remove-Item -Recurse -Force $work
    Write-Host "Fertig: Dateien verfügbar unter https://$owner.github.io/$repo/"
    Write-Host "Prüfe: https://$owner.github.io/$repo/version.json"
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
