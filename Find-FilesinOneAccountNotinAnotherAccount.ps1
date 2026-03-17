<#
.SYNOPSIS
Compare blob filenames between a primary Knowledge Base container path and a secondary container.

.DESCRIPTION
This script:
1) Lists unique blob "leaf" filenames under a specific prefix in the PRIMARY storage account/container.
2) Lists blob "leaf" filenames in the SECONDARY storage account/container, then filters out split PDFs
   (e.g., excludes files ending in "-0.pdf", "-1.pdf", etc.).
3) Compares the two lists and reports:
   - Files present in PRIMARY but missing from SECONDARY
   - Files present in SECONDARY but missing from PRIMARY

.NOTES
Requirements:
- Az.Accounts and Az.Storage modules installed.
- You must be authenticated (Connect-AzAccount) and have data-plane permissions such as:
  "Storage Blob Data Reader" (minimum) on both storage accounts/containers.

Assumptions:
- Blob filenames are compared by leaf name only (everything after the last "/").
- Secondary "split" files follow the pattern: "-<digits>.pdf" at the end of the filename.

.EXAMPLE
# Run interactively after signing in:
Connect-AzAccount
Set-AzContext -Subscription "AI Services"
.\Compare-KnowledgeBaseBlobs.ps1
#>

# -----------------------------
# Authentication (recommended)
# -----------------------------
# For interactive use:
# Connect-AzAccount
# Set-AzContext -Subscription "AI Services"
#
# Tip: If you work across tenants, you may need:
# Connect-AzAccount -TenantId "<tenant-guid>"

# -----------------------------
# PRIMARY: list files from KB container + prefix
# -----------------------------
# PRIMARY is the authoritative set of documents under a "folder-like" prefix.
$storageAccountPrimary = "stgen2ja3c6n6gralaw"
$containerNamePrimary  = "gptkbcontainer"
$prefixPrimary         = "organization/12/knowledge-base/63332cde-cf43-45e2-be89-6a3e1a10f3e8/"

# Create a storage context using the signed-in identity (Entra ID auth).
$ctxPrimary = New-AzStorageContext -StorageAccountName $storageAccountPrimary -UseConnectedAccount

# Pull blobs under the prefix and convert to leaf filenames:
# - ExpandProperty Name yields full blob name (including prefix path)
# - Split-Path -Leaf returns only the final filename
# - Sort -Unique ensures a clean, unique comparison set
$filesname = @(
    Get-AzStorageBlob -Container $containerNamePrimary -Context $ctxPrimary -Prefix $prefixPrimary |
        Select-Object -ExpandProperty Name |
        ForEach-Object { Split-Path $_ -Leaf } |
        Sort-Object -Unique
)

# -----------------------------
# SECONDARY: list base files (exclude "-0.pdf", "-1.pdf", etc.)
# -----------------------------
# SECONDARY is where split PDFs may exist; we want only the "base" documents.
$storageAccountSecondary = "stja3c6n6gralaw"
$containerNameSecondary  = "63332cde-cf43-45e2-be89-6a3e1a10f3e8"

$ctxSecondary = New-AzStorageContext -StorageAccountName $storageAccountSecondary -UseConnectedAccount

# List all blobs in the secondary container and convert to leaf filenames.
$fileNames = @(
    Get-AzStorageBlob -Container $containerNameSecondary -Context $ctxSecondary |
        Select-Object -ExpandProperty Name |
        ForEach-Object { Split-Path $_ -Leaf }
)

# Filter out split parts (e.g., "Document-0.pdf", "Document-1.pdf") and keep unique base docs.
# Regex explanation:
#   -\d+\.pdf$  => dash + one or more digits + ".pdf" at the end of the string
$baseOnly = @(
    $fileNames |
        Where-Object { $_ -notmatch '-\d+\.pdf$' } |
        Sort-Object -Unique
)

# -----------------------------
# COMPARE: find differences between PRIMARY and SECONDARY base docs
# -----------------------------
# Compare-Object:
# - ReferenceObject: treat PRIMARY as the baseline set
# - DifferenceObject: treat SECONDARY (baseOnly) as the comparison set
$diff = Compare-Object -ReferenceObject $filesname -DifferenceObject $baseOnly

# SideIndicator meanings:
#   "<=" => present in ReferenceObject (PRIMARY) but NOT in DifferenceObject (SECONDARY base)
#   "=>" => present in DifferenceObject (SECONDARY base) but NOT in ReferenceObject (PRIMARY)
#
# Use @() array subexpression so .Count works reliably even when results are 0 or 1 items.
$missingFromSecondary = @(
    $diff |
        Where-Object SideIndicator -eq "<=" |
        Select-Object -ExpandProperty InputObject
)

$missingFromPrimary = @(
    $diff |
        Where-Object SideIndicator -eq "=>" |
        Select-Object -ExpandProperty InputObject
)

# -----------------------------
# SUMMARY OUTPUT
# -----------------------------
# Note: Write-Host is fine for interactive use. For automation, consider Write-Output/Write-Verbose.
"Primary count     : $($filesname.Count)"
"Secondary base ct : $($baseOnly.Count)"
"Missing from secondary (present in primary, not in secondary): $($missingFromSecondary.Count)"
"Missing from primary   (present in secondary, not in primary): $($missingFromPrimary.Count)"

"`n--- Missing from $storageAccountSecondary (present in PRIMARY only) ---"
$missingFromSecondary | Sort-Object

"`n--- Missing from $storageAccountPrimary (present in SECONDARY only) ---"
$missingFromPrimary | Sort-Object
