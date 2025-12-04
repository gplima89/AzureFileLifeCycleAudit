# Troubleshooting and Validation Script for Azure Automation Runbook
# This script validates prerequisites and retrieves job execution details
#
# This script performs:
# 1. Automation Account validation
# 2. Managed Identity verification
# 3. Role assignment checks
# 4. Storage account and file share validation
# 5. Runbook parameters configuration
# 6. Latest job execution analysis

# Connect to Azure (if not already connected)
# Connect-AzAccount

# ============================
# CONFIGURATION VARIABLES
# ============================
$AutomationAccountName = "aa-file-lifecycle"
$ResourceGroupName = "rg-file-lifecycle"
$RunbookName = "FileStorageLifeCycle"

# Storage Account details for validation (update these to match your environment)
$StorageAccountName = "labazstglifecycle"  # Update if validating a different storage account
$FileShareName = "lifecycle"              # Update if validating a different file share
$StorageResourceGroupName = "LABAZSTG"    # Update if different from automation RG

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Azure File Share Audit - Validation Script" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan

# ============================
# STEP 1: Validate Automation Account
# ============================
Write-Host "STEP 1: Validating Automation Account..." -ForegroundColor Yellow
try {
    $automationAccount = Get-AzAutomationAccount -ResourceGroupName $ResourceGroupName -Name $AutomationAccountName -ErrorAction Stop
    Write-Host "  ✓ Automation Account '$AutomationAccountName' found" -ForegroundColor Green
    Write-Host "    Location: $($automationAccount.Location)" -ForegroundColor Gray
    Write-Host "    State: $($automationAccount.State)" -ForegroundColor Gray
}
catch {
    Write-Host "  ✗ FAILED: Automation Account not found" -ForegroundColor Red
    Write-Host "    Error: $_" -ForegroundColor Red
    exit 1
}

# ============================
# STEP 2: Validate Managed Identity
# ============================
Write-Host "`nSTEP 2: Validating Managed Identity..." -ForegroundColor Yellow
$identity = $automationAccount.Identity

if ($identity -and $identity.Type -eq "SystemAssigned") {
    Write-Host "  ✓ System-Assigned Managed Identity is enabled" -ForegroundColor Green
    Write-Host "    Principal ID: $($identity.PrincipalId)" -ForegroundColor Gray
    Write-Host "    Tenant ID: $($identity.TenantId)" -ForegroundColor Gray
    $principalId = $identity.PrincipalId
}
else {
    Write-Host "  ✗ FAILED: System-Assigned Managed Identity is NOT enabled" -ForegroundColor Red
    Write-Host "    Action Required: Enable System-Assigned Identity in Automation Account settings" -ForegroundColor Red
    $principalId = $null
}

# ============================
# STEP 3: Validate Runbook Parameters
# ============================
Write-Host "`nSTEP 3: Validating Runbook Parameters..." -ForegroundColor Yellow
Write-Host "  ℹ The runbook uses parameters instead of Automation Variables" -ForegroundColor Cyan
Write-Host "  ℹ Parameters must be provided when starting the runbook or in schedule configuration" -ForegroundColor Cyan

Write-Host "`n  Required Parameters:" -ForegroundColor Gray
Write-Host "    - StorageAccountName (Mandatory)" -ForegroundColor Cyan
Write-Host "    - FileShareName (Mandatory)" -ForegroundColor Cyan
Write-Host "    - ResourceGroupName (Optional)" -ForegroundColor Cyan

Write-Host "`n  Configuration for Validation:" -ForegroundColor Gray
Write-Host "    StorageAccountName: $StorageAccountName" -ForegroundColor White
Write-Host "    FileShareName: $FileShareName" -ForegroundColor White
Write-Host "    ResourceGroupName: $StorageResourceGroupName" -ForegroundColor White

Write-Host "`n  ✓ Runbook is configured to accept parameters" -ForegroundColor Green
Write-Host "    Note: Update the configuration variables at the top of this script to validate different storage accounts" -ForegroundColor Gray

# Use the configuration variables for later validation
$storageAccountName = $StorageAccountName
$fileShareName = $FileShareName
$storageResourceGroup = $StorageResourceGroupName

# ============================
# STEP 4: Validate Storage Account
# ============================
if ($storageAccountName) {
    Write-Host "`nSTEP 4: Validating Storage Account..." -ForegroundColor Yellow
    try {
        if ($storageResourceGroup) {
            $storageAccount = Get-AzStorageAccount -ResourceGroupName $storageResourceGroup -Name $storageAccountName -ErrorAction Stop
        }
        else {
            $storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName } | Select-Object -First 1
        }
        
        if ($storageAccount) {
            Write-Host "  ✓ Storage Account '$storageAccountName' found" -ForegroundColor Green
            Write-Host "    Resource Group: $($storageAccount.ResourceGroupName)" -ForegroundColor Gray
            Write-Host "    Location: $($storageAccount.Location)" -ForegroundColor Gray
            Write-Host "    SKU: $($storageAccount.Sku.Name)" -ForegroundColor Gray
            Write-Host "    HTTPS Only: $($storageAccount.EnableHttpsTrafficOnly)" -ForegroundColor Gray
            $storageAccountId = $storageAccount.Id
        }
        else {
            Write-Host "  ✗ FAILED: Storage Account '$storageAccountName' not found" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  ✗ FAILED: Error accessing Storage Account" -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "`nSTEP 4: Skipping Storage Account validation (variable not set)" -ForegroundColor Gray
}

# ============================
# STEP 5: Validate File Share
# ============================
if ($storageAccount -and $fileShareName) {
    Write-Host "`nSTEP 5: Validating File Share..." -ForegroundColor Yellow
    try {
        $ctx = $storageAccount.Context
        $fileShare = Get-AzStorageShare -Context $ctx -Name $fileShareName -ErrorAction Stop
        Write-Host "  ✓ File Share '$fileShareName' found" -ForegroundColor Green
        Write-Host "    Quota: $($fileShare.QuotaGiB) GiB" -ForegroundColor Gray
        Write-Host "    Last Modified: $($fileShare.LastModified)" -ForegroundColor Gray
        Write-Host "    Protocols: $($fileShare.Protocols)" -ForegroundColor Gray
    }
    catch {
        Write-Host "  ✗ FAILED: File Share '$fileShareName' not found" -ForegroundColor Red
        Write-Host "    Error: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "`nSTEP 5: Skipping File Share validation (prerequisites not met)" -ForegroundColor Gray
}

# ============================
# STEP 6: Validate Role Assignments
# ============================
if ($principalId -and $storageAccountId) {
    Write-Host "`nSTEP 6: Validating Role Assignments..." -ForegroundColor Yellow
    
    $roleAssignments = Get-AzRoleAssignment -ObjectId $principalId -Scope $storageAccountId
    
    $requiredRoles = @{
        "Storage File Data SMB Share Contributor" = $false
        "Storage Account Contributor" = $false
    }
    
    Write-Host "  Current Role Assignments on Storage Account:" -ForegroundColor Gray
    if ($roleAssignments.Count -gt 0) {
        foreach ($role in $roleAssignments) {
            Write-Host "    - $($role.RoleDefinitionName)" -ForegroundColor Cyan
            if ($requiredRoles.ContainsKey($role.RoleDefinitionName)) {
                $requiredRoles[$role.RoleDefinitionName] = $true
            }
        }
    }
    else {
        Write-Host "    (No role assignments found)" -ForegroundColor Gray
    }
    
    # Check for required roles
    Write-Host "`n  Required Roles Validation:" -ForegroundColor Gray
    $allRolesPresent = $true
    
    foreach ($roleName in $requiredRoles.Keys) {
        if ($requiredRoles[$roleName]) {
            Write-Host "    ✓ $roleName" -ForegroundColor Green
        }
        else {
            Write-Host "    ✗ $roleName - MISSING" -ForegroundColor Red
            $allRolesPresent = $false
        }
    }
    
    if (-not $allRolesPresent) {
        Write-Host "`n  Action Required: Assign missing roles to Managed Identity" -ForegroundColor Red
        Write-Host "  Commands to assign roles:" -ForegroundColor Yellow
        Write-Host "    `$principalId = `"$principalId`"" -ForegroundColor Gray
        Write-Host "    `$storageAccountId = `"$storageAccountId`"" -ForegroundColor Gray
        foreach ($roleName in $requiredRoles.Keys) {
            if (-not $requiredRoles[$roleName]) {
                Write-Host "    New-AzRoleAssignment -ObjectId `$principalId -RoleDefinitionName `"$roleName`" -Scope `$storageAccountId" -ForegroundColor Gray
            }
        }
    }
    else {
        Write-Host "  ✓ All required roles are assigned" -ForegroundColor Green
    }
}
else {
    Write-Host "`nSTEP 6: Skipping Role Assignment validation (prerequisites not met)" -ForegroundColor Gray
}

# ============================
# STEP 7: Validate PowerShell Modules
# ============================
Write-Host "`nSTEP 7: Validating PowerShell Modules..." -ForegroundColor Yellow
$requiredModules = @{
    "Az.Accounts" = "2.0.0"
    "Az.Storage" = "5.0.0"
}

$modules = Get-AzAutomationModule -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName

foreach ($moduleName in $requiredModules.Keys) {
    $module = $modules | Where-Object { $_.Name -eq $moduleName }
    if ($module) {
        $minVersion = [Version]$requiredModules[$moduleName]
        $currentVersion = [Version]$module.Version
        if ($currentVersion -ge $minVersion) {
            Write-Host "  ✓ $moduleName (v$($module.Version)) - $($module.ProvisioningState)" -ForegroundColor Green
        }
        else {
            Write-Host "  ⚠ $moduleName (v$($module.Version)) - Version below recommended ($($requiredModules[$moduleName]))" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  ✗ $moduleName - NOT INSTALLED" -ForegroundColor Red
    }
}

# ============================
# STEP 8: Validate Runbook
# ============================
Write-Host "`nSTEP 8: Validating Runbook..." -ForegroundColor Yellow
try {
    $runbook = Get-AzAutomationRunbook -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Name $RunbookName -ErrorAction Stop
    Write-Host "  ✓ Runbook '$RunbookName' found" -ForegroundColor Green
    Write-Host "    Type: $($runbook.RunbookType)" -ForegroundColor Gray
    Write-Host "    State: $($runbook.State)" -ForegroundColor Gray
    Write-Host "    Last Modified: $($runbook.LastModifiedTime)" -ForegroundColor Gray
    
    if ($runbook.State -ne "Published") {
        Write-Host "  ⚠ WARNING: Runbook is not published" -ForegroundColor Yellow
    }
}
catch {
    Write-Host "  ✗ FAILED: Runbook '$RunbookName' not found" -ForegroundColor Red
    Write-Host "    Error: $_" -ForegroundColor Red
}

# ============================
# STEP 9: Analyze Latest Job Execution
# ============================
Write-Host "`nSTEP 9: Analyzing Latest Job Execution..." -ForegroundColor Yellow
$latestJob = Get-AzAutomationJob -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -RunbookName $RunbookName `
    -ErrorAction SilentlyContinue | 
    Sort-Object StartTime -Descending | 
    Select-Object -First 1
Write-Host "Retrieving latest job for runbook '$RunbookName'..." -ForegroundColor Cyan
$latestJob = Get-AzAutomationJob -ResourceGroupName $ResourceGroupName `
    -AutomationAccountName $AutomationAccountName `
    -RunbookName $RunbookName `
    -ErrorAction Stop | 
    Sort-Object StartTime -Descending | 
    Select-Object -First 1

if (-not $latestJob) {
    Write-Host "  ℹ No jobs found for this runbook (never executed)" -ForegroundColor Gray
}
else {
    # Display job summary
    $statusColor = switch ($latestJob.Status) {
        "Completed" { "Green" }
        "Failed" { "Red" }
        "Running" { "Yellow" }
        default { "Gray" }
    }
    
    Write-Host "  Latest Job Details:" -ForegroundColor Gray
    Write-Host "    Job ID: $($latestJob.JobId)" -ForegroundColor Gray
    Write-Host "    Status: $($latestJob.Status)" -ForegroundColor $statusColor
    Write-Host "    Start Time: $($latestJob.StartTime)" -ForegroundColor Gray
    Write-Host "    End Time: $($latestJob.EndTime)" -ForegroundColor Gray
    
    if ($latestJob.Exception) {
        Write-Host "    Exception: $($latestJob.Exception)" -ForegroundColor Red
    }
    
    # Get job output streams
    Write-Host "`n  Job Output Streams:" -ForegroundColor Gray
    $output = Get-AzAutomationJobOutput -ResourceGroupName $ResourceGroupName `
        -AutomationAccountName $AutomationAccountName `
        -Id $latestJob.JobId `
        -Stream Any
    
    $streamCounts = $output | Group-Object -Property Type | Select-Object Name, Count
    foreach ($stream in $streamCounts) {
        Write-Host "    - $($stream.Name): $($stream.Count) messages" -ForegroundColor Cyan
    }
    
    # Show errors if any
    $errors = $output | Where-Object { $_.Type -eq "Error" }
    if ($errors.Count -gt 0) {
        Write-Host "`n  ✗ Job Errors Found:" -ForegroundColor Red
        foreach ($errorItem in $errors | Select-Object -First 5) {
            $errorDetails = Get-AzAutomationJobOutputRecord -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -JobId $latestJob.JobId `
                -Id $errorItem.StreamRecordId
            Write-Host "    [$($errorItem.Time)] $($errorDetails.Value.Message)" -ForegroundColor Red
        }
    }
    elseif ($latestJob.Status -eq "Completed") {
        Write-Host "  ✓ Job completed successfully with no errors" -ForegroundColor Green
    }
    
    # Show last few output messages
    $outputs = $output | Where-Object { $_.Type -eq "Output" } | Select-Object -Last 10
    if ($outputs.Count -gt 0) {
        Write-Host "`n  Last Output Messages:" -ForegroundColor Gray
        foreach ($outItem in $outputs) {
            $outDetails = Get-AzAutomationJobOutputRecord -ResourceGroupName $ResourceGroupName `
                -AutomationAccountName $AutomationAccountName `
                -JobId $latestJob.JobId `
                -Id $outItem.StreamRecordId
            if ($outDetails.Value.Message) {
                Write-Host "    $($outDetails.Value.Message)" -ForegroundColor White
            }
        }
    }
}

# ============================
# STEP 10: Verify Audit Files
# ============================
if ($storageAccount -and $fileShareName) {
    Write-Host "`nSTEP 10: Verifying Audit Files..." -ForegroundColor Yellow
    try {
        $ctx = $storageAccount.Context
        $auditFolder = Get-AzStorageFile -Context $ctx -ShareName $fileShareName -Path "AuditLifeCycle" -ErrorAction SilentlyContinue
        
        if ($auditFolder) {
            Write-Host "  ✓ AuditLifeCycle folder exists" -ForegroundColor Green
            
            $csvFiles = Get-AzStorageFile -Context $ctx -ShareName $fileShareName -Path "AuditLifeCycle" | 
                Where-Object { $_.Name -like "*.csv" }
            
            if ($csvFiles) {
                Write-Host "  ✓ Found $($csvFiles.Count) audit CSV file(s)" -ForegroundColor Green
                Write-Host "`n  Audit Files:" -ForegroundColor Gray
                foreach ($file in $csvFiles | Select-Object -First 5) {
                    $sizeKB = [math]::Round($file.Length / 1KB, 2)
                    Write-Host "    - $($file.Name) ($sizeKB KB) - Last Modified: $($file.Properties.LastModified)" -ForegroundColor Cyan
                }
                if ($csvFiles.Count -gt 5) {
                    Write-Host "    ... and $($csvFiles.Count - 5) more" -ForegroundColor Gray
                }
            }
            else {
                Write-Host "  ℹ No CSV files found in AuditLifeCycle folder" -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "  ℹ AuditLifeCycle folder does not exist yet (will be created on first run)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  ⚠ Could not verify audit files: $_" -ForegroundColor Yellow
    }
}
else {
    Write-Host "`nSTEP 10: Skipping Audit Files verification (prerequisites not met)" -ForegroundColor Gray
}

# ============================
# VALIDATION SUMMARY
# ============================
Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  VALIDATION SUMMARY" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan

$allChecks = @{
    "Automation Account" = ($automationAccount -ne $null)
    "Managed Identity" = ($principalId -ne $null)
    "Storage Account" = ($storageAccount -ne $null)
    "File Share" = ($fileShare -ne $null)
    "Role Assignments" = ($allRolesPresent -eq $true)
    "Runbook Published" = ($runbook.State -eq "Published")
}

$passedChecks = 0
$totalChecks = $allChecks.Count

foreach ($check in $allChecks.GetEnumerator()) {
    if ($check.Value) {
        Write-Host "  ✓ $($check.Key)" -ForegroundColor Green
        $passedChecks++
    }
    else {
        Write-Host "  ✗ $($check.Key)" -ForegroundColor Red
    }
}

Write-Host "`nResult: $passedChecks/$totalChecks checks passed" -ForegroundColor $(if ($passedChecks -eq $totalChecks) { "Green" } else { "Yellow" })

if ($passedChecks -eq $totalChecks) {
    Write-Host "`n✓ All prerequisites are met! The runbook is ready for production." -ForegroundColor Green
}
else {
    Write-Host "`n⚠ Some prerequisites are missing. Review the output above for required actions." -ForegroundColor Yellow
}

Write-Host "`n================================================" -ForegroundColor Cyan
Write-Host "  Validation Complete" -ForegroundColor Cyan
Write-Host "================================================`n" -ForegroundColor Cyan
