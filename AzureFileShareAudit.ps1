<#
.SYNOPSIS
    Azure File Share Audit Script for Azure Automation

.DESCRIPTION
    This script lists all files in an Azure Storage File Share, captures their metadata,
    and creates a timestamped CSV audit file. It maintains audit files for the past 31 days,
    removing older ones automatically.

.NOTES
    Designed to run in an Azure Automation Account
    Requires Azure PowerShell modules: Az.Storage
    Uses Managed Identity for authentication
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$StorageAccountName,
    
    [Parameter(Mandatory=$true)]
    [string]$FileShareName,
    
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroupName
)

# Connect to Azure using Managed Identity
try {
    Write-Output "Connecting to Azure using Managed Identity..."
    Connect-AzAccount -Identity -ErrorAction Stop
    Write-Output "Successfully connected to Azure"
}
catch {
    Write-Error "Failed to connect to Azure: $_"
    throw
}

# Get Storage Account Context
try {
    Write-Output "Getting storage account context..."
    if ($ResourceGroupName) {
        $storageAccount = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction Stop
    }
    else {
        $storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $StorageAccountName } | Select-Object -First 1
        if (-not $storageAccount) {
            throw "Storage account '$StorageAccountName' not found"
        }
    }
    
    $ctx = $storageAccount.Context
    Write-Output "Successfully obtained storage context for '$StorageAccountName'"
}
catch {
    Write-Error "Failed to get storage account context: $_"
    throw
}

# Function to recursively get all files from a directory
function Get-AzFileShareFilesRecursive {
    param(
        [Parameter(Mandatory=$true)]
        $Context,
        
        [Parameter(Mandatory=$true)]
        [string]$ShareName,
        
        [Parameter(Mandatory=$false)]
        [string]$Path = ""
    )
    
    $files = @()
    
    try {
        # Get all items in the current directory
        $items = Get-AzStorageFile -Context $Context -ShareName $ShareName -Path $Path -ErrorAction Stop
        
        foreach ($item in $items) {
            if ($item.GetType().Name -eq "AzureStorageFileDirectory" -or $item.IsDirectory) {
                # If it's a directory, recurse into it
                $subPath = if ($Path) { "$Path/$($item.Name)" } else { $item.Name }
                $files += Get-AzFileShareFilesRecursive -Context $Context -ShareName $ShareName -Path $subPath
            }
            else {
                # If it's a file, get its properties and add to collection
                $filePath = if ($Path) { "$Path/$($item.Name)" } else { $item.Name }
                
                # Fetch detailed properties
                $fileProperties = Get-AzStorageFile -Context $Context -ShareName $ShareName -Path $filePath | Get-AzStorageFile
                
                $fileInfo = [PSCustomObject]@{
                    FileName = $item.Name
                    FullPath = $filePath
                    Directory = $Path
                    SizeBytes = $item.Length
                    SizeKB = [math]::Round($item.Length / 1KB, 2)
                    SizeMB = [math]::Round($item.Length / 1MB, 2)
                    LastModified = $item.Properties.LastModified
                    ETag = $item.Properties.ETag
                    ContentType = $item.Properties.ContentType
                    IsServerEncrypted = $item.Properties.IsServerEncrypted
                    FileId = $item.Properties.FileId
                    ParentId = $item.Properties.ParentId
                    AuditDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
                    StorageAccountName = $StorageAccountName
                    FileShareName = $ShareName
                }
                
                $files += $fileInfo
            }
        }
    }
    catch {
        Write-Warning "Error accessing path '$Path': $_"
    }
    
    return $files
}

# Collect all files from the file share
try {
    Write-Output "Starting file enumeration in share '$FileShareName'..."
    $allFiles = Get-AzFileShareFilesRecursive -Context $ctx -ShareName $FileShareName
    Write-Output "Found $($allFiles.Count) files in the file share"
}
catch {
    Write-Error "Failed to enumerate files: $_"
    throw
}

# Create the AuditLifeCycle directory if it doesn't exist
$auditFolderPath = "AuditLifeCycle"
try {
    Write-Output "Checking if audit folder exists..."
    $folder = Get-AzStorageFile -Context $ctx -ShareName $FileShareName -Path $auditFolderPath -ErrorAction SilentlyContinue
    
    if (-not $folder) {
        Write-Output "Creating audit folder '$auditFolderPath'..."
        New-AzStorageDirectory -Context $ctx -ShareName $FileShareName -Path $auditFolderPath -ErrorAction Stop
        Write-Output "Audit folder created successfully"
    }
    else {
        Write-Output "Audit folder already exists"
    }
}
catch {
    Write-Error "Failed to create audit folder: $_"
    throw
}

# Generate CSV filename with timestamp
$timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
$csvFileName = "LifeCycleAudit_$timestamp.csv"
$csvPath = "$auditFolderPath/$csvFileName"

# Export to CSV and upload to file share
try {
    Write-Output "Generating CSV file..."
    $tempCsvPath = Join-Path $env:TEMP $csvFileName
    
    # Export files to CSV
    if ($allFiles.Count -gt 0) {
        $allFiles | Export-Csv -Path $tempCsvPath -NoTypeInformation -Encoding UTF8
    }
    else {
        # Create empty CSV with headers
        [PSCustomObject]@{
            FileName = ""
            FullPath = ""
            Directory = ""
            SizeBytes = ""
            SizeKB = ""
            SizeMB = ""
            LastModified = ""
            ETag = ""
            ContentType = ""
            IsServerEncrypted = ""
            FileId = ""
            ParentId = ""
            AuditDate = ""
            StorageAccountName = ""
            FileShareName = ""
        } | Export-Csv -Path $tempCsvPath -NoTypeInformation -Encoding UTF8
        
        # Remove the empty data row, keep only header
        $content = Get-Content $tempCsvPath
        $content[0] | Set-Content $tempCsvPath
    }
    
    Write-Output "Uploading CSV file to '$csvPath'..."
    Set-AzStorageFileContent -Context $ctx -ShareName $FileShareName -Source $tempCsvPath -Path $csvPath -Force -ErrorAction Stop
    Write-Output "CSV file uploaded successfully"
    
    # Clean up temp file
    Remove-Item $tempCsvPath -Force -ErrorAction SilentlyContinue
}
catch {
    Write-Error "Failed to create or upload CSV file: $_"
    throw
}

# Clean up old audit files (keep only last 31 days)
try {
    Write-Output "Cleaning up old audit files..."
    $cutoffDate = (Get-Date).AddDays(-31)
    
    # Get all files in the audit folder
    $auditFiles = Get-AzStorageFile -Context $ctx -ShareName $FileShareName -Path $auditFolderPath -ErrorAction Stop
    
    $deletedCount = 0
    foreach ($auditFile in $auditFiles) {
        if ($auditFile.GetType().Name -ne "AzureStorageFileDirectory" -and -not $auditFile.IsDirectory) {
            # Check if file is older than 31 days
            if ($auditFile.Properties.LastModified -lt $cutoffDate) {
                $fileToDelete = "$auditFolderPath/$($auditFile.Name)"
                Write-Output "Deleting old audit file: $fileToDelete (Last Modified: $($auditFile.Properties.LastModified))"
                Remove-AzStorageFile -Context $ctx -ShareName $FileShareName -Path $fileToDelete -ErrorAction Stop
                $deletedCount++
            }
        }
    }
    
    Write-Output "Cleanup complete. Deleted $deletedCount old audit file(s)"
}
catch {
    Write-Warning "Error during cleanup of old files: $_"
    # Don't throw - cleanup failure shouldn't fail the entire script
}

# Summary
Write-Output "`n=== Audit Summary ==="
Write-Output "Storage Account: $StorageAccountName"
Write-Output "File Share: $FileShareName"
Write-Output "Total Files Audited: $($allFiles.Count)"
Write-Output "Audit File Created: $csvPath"
Write-Output "Audit Completed: $(Get-Date)"
Write-Output "===================="
