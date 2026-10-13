param([Parameter(Mandatory = $true)][string]$Backup)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Set-Location -LiteralPath $PSScriptRoot

function Assert-Keys($Value, [string[]]$Keys) {
    if ($null -eq $Value -or (@($Value.PSObject.Properties.Name | Sort-Object) -join ',') -cne (($Keys | Sort-Object) -join ',')) {
        throw 'Invalid backup envelope: unexpected or missing fields.'
    }
}
function Assert-Bytes($Value, [int]$Minimum, [int]$Exact = 0) {
    if ($Value -isnot [array] -or $Value.Count -lt $Minimum -or ($Exact -gt 0 -and $Value.Count -ne $Exact)) { throw 'Invalid encrypted byte array.' }
    foreach ($Byte in $Value) {
        if (($Byte -isnot [int] -and $Byte -isnot [long]) -or $Byte -lt 0 -or $Byte -gt 255) { throw 'Backup contains non-encrypted data.' }
    }
}
function Assert-Record($Record) {
    Assert-Keys $Record @('id', 'nonce', 'ciphertext')
    Assert-Bytes $Record.nonce 24 24
    Assert-Bytes $Record.ciphertext 16
}

Get-Command git, gh -ErrorAction Stop | Out-Null
$Source = Get-Item -LiteralPath $Backup
if ($Source.PSIsContainer -or $Source.Length -gt 268435456) { throw 'Choose an exported Atlas encrypted JSON backup (maximum 256 MiB).' }
$Document = Get-Content -Raw -LiteralPath $Source.FullName | ConvertFrom-Json
Assert-Keys $Document @('format', 'version', 'meta', 'records')
if ($Document.format -cne 'amiya-atlas-backup' -or $Document.version -ne 1) { throw 'This is not an Atlas encrypted backup. Do not upload exports or SQLite files.' }
$Meta = $Document.meta
Assert-Keys $Meta @('vaultId', 'formatVersion', 'kdfName', 'kdfParams', 'salt', 'cipherSuite', 'wrappedKey')
$Uuid = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
if ($Meta.vaultId -cnotmatch $Uuid -or $Meta.formatVersion -ne 1 -or $Meta.kdfName -cne 'Argon2id' -or $Meta.cipherSuite -cne 'XChaCha20-Poly1305') { throw 'Unsupported encryption metadata.' }
Assert-Keys $Meta.kdfParams @('memoryKib', 'iterations', 'lanes')
if ($Meta.kdfParams.memoryKib -lt 8192 -or $Meta.kdfParams.memoryKib -gt 262144 -or $Meta.kdfParams.iterations -lt 1 -or $Meta.kdfParams.iterations -gt 10 -or $Meta.kdfParams.lanes -lt 1 -or $Meta.kdfParams.lanes -gt 8) { throw 'Unsupported key derivation parameters.' }
Assert-Bytes $Meta.salt 16 16
Assert-Record $Meta.wrappedKey
if ($Meta.wrappedKey.id -cne 'key' -or $Meta.wrappedKey.ciphertext.Count -ne 48) { throw 'Invalid wrapped vault key.' }
if ($Document.records -isnot [array] -or $Document.records.Count -lt 1 -or $Document.records.Count -gt 260002) { throw 'Invalid encrypted records.' }
$Ids = @{}
foreach ($Record in $Document.records) {
    Assert-Record $Record
    if (($Record.id -cne 'manifest' -and $Record.id -cnotmatch $Uuid) -or $Ids.ContainsKey($Record.id)) { throw 'Invalid encrypted record identifier.' }
    $Ids[$Record.id] = $true
}
if (!$Ids.ContainsKey('manifest')) { throw 'Backup integrity manifest is missing.' }

$Root = git rev-parse --show-toplevel
if ($LASTEXITCODE -ne 0 -or [IO.Path]::GetFullPath($Root) -ne [IO.Path]::GetFullPath($PSScriptRoot)) { throw 'Clone the template as its own repository first.' }
$Remote = git remote get-url origin
if ($LASTEXITCODE -ne 0 -or $Remote -notmatch '^(?:https://github\.com/|git@github\.com:)([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?$') { throw 'Origin must be your private GitHub repository.' }
$Repository = $Matches[1]
$Private = gh api "repos/$Repository" --jq '.private'
if ($LASTEXITCODE -ne 0 -or $Private -cne 'true') { throw 'Upload blocked: GitHub repository is public or its visibility could not be confirmed.' }
$Staged = git diff --cached --name-only
if ($LASTEXITCODE -ne 0 -or $Staged) { throw 'Other files are staged. Commit or unstage them yourself before backing up.' }
$Branch = git symbolic-ref --quiet --short HEAD
if ($LASTEXITCODE -ne 0 -or !$Branch) { throw 'Select a branch before backing up.' }
git fetch --no-tags origin $Branch
if ($LASTEXITCODE -ne 0) { throw 'Could not read the remote branch. Push your template setup separately first.' }
git merge-base --is-ancestor FETCH_HEAD HEAD
if ($LASTEXITCODE -ne 0) { throw 'Remote changes exist. Pull them before backing up.' }
$ChangedPaths = git log --format= --name-only 'FETCH_HEAD..HEAD'
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect pending commits.' }
if (@($ChangedPaths | Where-Object { $_ -and $_ -cne 'vault/latest.atlas-backup.json' }).Count -gt 0) {
    throw 'Push blocked: pending commits include files other than the encrypted backup. Review and push those changes yourself first.'
}

$Destination = Join-Path $PSScriptRoot 'vault/latest.atlas-backup.json'
if ($Source.FullName -ne $Destination) { Copy-Item -LiteralPath $Source.FullName -Destination $Destination }
git add -- 'vault/latest.atlas-backup.json'
if ($LASTEXITCODE -ne 0) { throw 'Could not stage encrypted backup.' }
git diff --cached --quiet -- 'vault/latest.atlas-backup.json'
if ($LASTEXITCODE -eq 1) {
    git commit -m 'Update encrypted Relakeep backup' -- 'vault/latest.atlas-backup.json'
    if ($LASTEXITCODE -ne 0) { throw 'Commit failed. Configure your Git name and email.' }
} elseif ($LASTEXITCODE -ne 0) { throw 'Could not read staged backup.' }
git -c push.followTags=false push origin "HEAD:refs/heads/$Branch"
if ($LASTEXITCODE -ne 0) { throw 'Push failed. Your encrypted backup remains local; fix access and run again.' }
Write-Host 'Encrypted backup saved to your private GitHub repository.'
