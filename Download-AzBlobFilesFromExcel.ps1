<#
.SYNOPSIS
Downloads a list of documents from an Azure Blob Storage container using exact blob-name matching.

.DESCRIPTION
- Reads a list of filenames from an Excel worksheet (Sheet1).
- Treats each value as an EXACT blob name (no prefix/path searching).
- Pre-lists blob names from the target container once and uses a HashSet for fast lookups.
- Downloads matched blobs to a flat local folder.
- Logs downloaded and missing files.

.PARAMETER storageAccount
Azure Storage account name hosting the container.

.PARAMETER containerName
Blob container name that contains the target documents.

.PARAMETER excelPath
Path to the Excel file containing the list of document names.

.PARAMETER downloadRoot
Local folder where documents and logs will be written.

.NOTES
Requirements:
- Az.Accounts + Az.Storage modules installed and available.
- ImportExcel module installed (or replace Import-Excel with a CSV/COM alternative).
Permissions:
- Requires data-plane access such as "Storage Blob Data Reader" (or higher) on the container/storage account.
Assumptions:
- The blob name in the container is exactly the filename (e.g., "MyDoc.pdf").
  If blobs are stored under a prefix (e.g., "folder/MyDoc.pdf"), this script will mark "MyDoc.pdf" as missing.

.EXAMPLE
.\Download-MissingDocs.ps1
#>

# -----------------------------
# Optional strictness controls
# -----------------------------
# Set-StrictMode -Version Latest
# $ErrorActionPreference = 'Stop'   # Consider enabling for stronger fail-fast behavior in automation.

# -----------------------------
# Module imports
# -----------------------------
# Import only what you use. If modules aren’t installed, the import will fail early.
# If you are running in an environment without ImportExcel, swap Import-Excel for a CSV/COM method.
Import-Module Az.Storage
Import-Module ImportExcel
####################################################################################################
#If you have an issue importing Excel Use these commands
# Trust PSGallery (only prompts once)
#Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

# Install ImportExcel for your user profile
#Install-Module ImportExcel -Scope CurrentUser -Force

# Load it
#Import-Module ImportExcel

# Verify
#Get-Module ImportExcel -ListAvailable
####################################################################################################

# -----------------------------
# Inputs / Configuration
# -----------------------------
# Storage account and container to search/download from.
$storageAccount = "stja3c6n6gralaw"
$containerName  = "63332cde-cf43-45e2-be89-6a3e1a10f3e8"

# Source list and output folder paths.
$excelPath    = "C:\MOFilesMissing\MOMVR Missing Documents Prod KB.xlsx"  # Excel file containing the filenames
$downloadRoot = "C:\MOFilesMissing\MOMVR-Missing-Docs"                    # Destination folder for downloads/logs

# -----------------------------
# Ensure output folder exists
# -----------------------------
# Create a flat download folder; files are saved directly under this path.
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null

# -----------------------------
# Authentication / Context
# -----------------------------
# Interactive login. In automation scenarios (runbooks, managed identity), this section would differ.
Connect-AzAccount | Out-Null

# If you have multiple subscriptions, set the correct one explicitly:
# Set-AzContext -Subscription "<subscription-id-or-name>"

# Build a storage context using the currently connected Entra ID identity.
$ctx = New-AzStorageContext -StorageAccountName $storageAccount -UseConnectedAccount

# -----------------------------
# Read filename list from Excel
# -----------------------------
# The worksheet is expected to contain a single column list of filenames,
# with a header row like "Missing from ..." that should be ignored.
$rows = Import-Excel -Path $excelPath -WorksheetName "Sheet1"

# Determine the first column’s property name dynamically (handles changing column headers).
$firstProp = ($rows | Select-Object -First 1 | Get-Member -MemberType NoteProperty | Select-Object -First 1).Name

# Build a clean list:
# - remove blanks
# - remove the header text line(s)
# - trim whitespace
# - unique values only
$fileList = @(
    $rows |
    ForEach-Object { $_.$firstProp } |
    Where-Object { $_ -and $_.Trim() -ne "" } |
    Where-Object { $_ -notmatch '^Missing from' } |
    ForEach-Object { $_.Trim() } |
    Sort-Object -Unique
)

Write-Host "Found $($fileList.Count) filenames in Excel."

# -----------------------------
# Pre-list blob names (one call) for performance
# -----------------------------
# For larger containers, pre-listing once is typically faster than querying for each blob.
# IMPORTANT: This script matches EXACT blob names only.
$allBlobNames = @(
    Get-AzStorageBlob -Container $containerName -Context $ctx |
    Select-Object -ExpandProperty Name
)

# Use a HashSet for O(1) membership tests (case-insensitive for convenience).
$blobNameSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$allBlobNames | ForEach-Object { [void]$blobNameSet.Add($_) }

# -----------------------------
# Logging setup
# -----------------------------
# Keep a timestamped log for traceability, plus a separate missing list file.
$logPath     = Join-Path $downloadRoot "download-log_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$missingPath = Join-Path $downloadRoot "missing-files.txt"

# Track results in-memory for summary reporting.
$missing    = New-Object System.Collections.Generic.List[string]
$downloaded = New-Object System.Collections.Generic.List[string]

# -----------------------------
# Download loop (EXACT name match only)
# -----------------------------
foreach ($fileName in $fileList) {

    # Skip anything that is not an exact match to an existing blob name.
    if (-not $blobNameSet.Contains($fileName)) {
        $missing.Add($fileName) | Out-Null
        Add-Content -Path $logPath -Value "MISSING (no exact blob name match): $fileName"
        Write-Host "MISSING: $fileName" -ForegroundColor Yellow
        continue
    }

    # Flat destination path (no subfolders created).
    $destPath = Join-Path $downloadRoot $fileName

    try {
        # Use -ErrorAction Stop to ensure failures are caught by catch.
        Get-AzStorageBlobContent `
            -Container $containerName `
            -Context $ctx `
            -Blob $fileName `
            -Destination $destPath `
            -Force `
            -ErrorAction Stop | Out-Null

        $downloaded.Add($fileName) | Out-Null
        Add-Content -Path $logPath -Value "DOWNLOADED: $fileName"
        Write-Host "DOWNLOADED: $fileName" -ForegroundColor Green
    }
    catch {
        # Capture any download failure as missing/failed and log the exception message.
        $missing.Add($fileName) | Out-Null
        Add-Content -Path $logPath -Value "ERROR: $fileName => $($_.Exception.Message)"
        Write-Host "ERROR: $fileName" -ForegroundColor Red
    }
}

# -----------------------------
# Summary / Output artifacts
# -----------------------------
Write-Host ""
Write-Host "Done."
Write-Host "Downloaded: $($downloaded.Count)"
Write-Host "Missing/Failed: $($missing.Count)"
Write-Host "Log: $logPath"

# Write a deduplicated missing list to disk to support re-runs.
if ($missing.Count -gt 0) {
    $missing | Sort-Object -Unique | Out-File -FilePath $missingPath
    Write-Host "Missing list saved: $missingPath" -ForegroundColor Yellow
}

# -----------------------------
# Optional: return objects instead of only console output
# -----------------------------
# In automation, consider outputting an object for downstream use:
# [pscustomobject]@{
#     Downloaded = $downloaded
#     Missing    = $missing
#     LogPath    = $logPath
# }
