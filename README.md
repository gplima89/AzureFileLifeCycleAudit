# Azure File Share Audit Script

## Overview

This PowerShell script automates the auditing of files in an Azure Storage File Share. It runs within an Azure Automation Account and generates detailed CSV reports containing metadata for all files in the specified file share.

## Objective

The primary objectives of this script are to:

1. **Enumerate all files** in an Azure Storage File Share recursively
2. **Capture comprehensive metadata** for each file (name, path, size, last modified date, etc.)
3. **Generate timestamped CSV audit reports** stored in the file share itself
4. **Maintain audit history** by keeping CSV files for the past 31 days and automatically removing older files
5. **Automate the process** through Azure Automation for scheduled or on-demand execution

## Features

- ✅ Recursive file enumeration across all directories
- ✅ Comprehensive metadata capture (15+ fields per file)
- ✅ Automatic audit folder creation (`AuditLifeCycle`)
- ✅ Timestamped CSV files for historical tracking
- ✅ Automatic cleanup of audit files older than 31 days
- ✅ Managed Identity authentication (secure, no credential management)
- ✅ Detailed logging and error handling

## Metadata Captured

Each file in the audit report includes:

| Field | Description |
|-------|-------------|
| FileName | Name of the file |
| FullPath | Complete path within the file share |
| Directory | Parent directory path |
| SizeBytes | File size in bytes |
| SizeKB | File size in kilobytes |
| SizeMB | File size in megabytes |
| LastModified | Last modification timestamp |
| ETag | Entity tag for version tracking |
| ContentType | MIME type of the file |
| IsServerEncrypted | Server-side encryption status |
| FileId | Unique file identifier |
| ParentId | Parent directory identifier |
| AuditDate | Date and time the audit was performed |
| StorageAccountName | Name of the storage account |
| FileShareName | Name of the file share |

## Prerequisites

### Azure Resources

1. **Azure Automation Account** - Where the runbook will execute
2. **Azure Storage Account** - Contains the file share to audit
3. **Azure File Share** - The storage location to be audited

### Permissions

The Azure Automation Account's Managed Identity requires:

- **Storage File Data SMB Share Contributor** role on the Storage Account or File Share

  OR

- **Storage File Data SMB Share Reader** role (for read-only access) + **Storage Account Contributor** role (for creating directories)

### PowerShell Modules

- **Az.Accounts** - For Azure authentication
- **Az.Storage** - For file share operations

*Note: These modules are typically pre-installed in Azure Automation Accounts*

## Setup Instructions

### Step 1: Create/Verify Azure Automation Account

1. Log in to the [Azure Portal](https://portal.azure.com)
2. Navigate to **Azure Automation Accounts**
3. Create a new Automation Account or use an existing one
4. Note the Automation Account name and resource group

### Step 2: Enable Managed Identity

1. In your Azure Automation Account, go to **Settings** > **Identity**
2. Under **System assigned** tab, toggle **Status** to **On**
3. Click **Save** and confirm
4. Copy the **Object (principal) ID** - you'll need this for permissions

### Step 3: Assign Storage Permissions

1. Navigate to your **Storage Account** in the Azure Portal
2. Go to **Access Control (IAM)**
3. Click **+ Add** > **Add role assignment**
4. Select the role:
   - **Storage File Data SMB Share Contributor** (recommended)
   - OR **Storage File Data SMB Share Reader** (if you prefer minimal permissions)
5. Click **Next**
6. Select **Managed Identity**
7. Click **+ Select members**
8. Filter by **Automation Account** and select your automation account
9. Click **Review + assign**

### Step 4: Verify/Import PowerShell Modules

1. In your Azure Automation Account, go to **Shared Resources** > **Modules**
2. Verify the following modules are present and up-to-date:
   - `Az.Accounts` (version 2.x or higher)
   - `Az.Storage` (version 5.x or higher)
3. If modules need updating:
   - Click **Browse gallery**
   - Search for the module name
   - Click **Import** and wait for completion

### Step 5: Configure Automation Variables

The script reads its configuration from Automation Account variables instead of parameters.

1. In your Azure Automation Account, go to **Shared Resources** > **Variables**
2. Click **+ Add a variable** to create each of the following:

   **Variable 1: StorageAccountName (Required)**
   - Name: `StorageAccountName`
   - Description: `Name of the Azure Storage Account`
   - Type: `String`
   - Value: Enter your storage account name (e.g., `mystorageaccount`)
   - Encrypted: `No`
   - Click **Create**

   **Variable 2: FileShareName (Required)**
   - Name: `FileShareName`
   - Description: `Name of the File Share to audit`
   - Type: `String`
   - Value: Enter your file share name (e.g., `myfileshare`)
   - Encrypted: `No`
   - Click **Create**

   **Variable 3: ResourceGroupName (Optional)**
   - Name: `ResourceGroupName`
   - Description: `Resource Group containing the Storage Account`
   - Type: `String`
   - Value: Enter your resource group name (e.g., `myresourcegroup`)
   - Encrypted: `No`
   - Click **Create**

3. Verify all variables are created and have the correct values

### Step 6: Import the Runbook

1. In your Azure Automation Account, go to **Process Automation** > **Runbooks**
2. Click **+ Create a runbook**
3. Enter a name: `AzureFileShareAudit`
4. Select **Runbook type**: **PowerShell**
5. Select **Runtime version**: **7.2** (or latest available)
6. Click **Create**
7. In the editor, paste the contents of `AzureFileShareAudit.ps1`
8. Click **Save**
9. Click **Publish** and confirm

### Step 7: Test the Runbook

1. In the runbook page, click **Start**
2. **No parameters are required** - the script will read from Automation Variables
3. Click **OK** to start the runbook
4. Monitor the **Output** tab for progress and results
5. Verify the output shows:
   - Successful connection to Azure
   - Retrieved configuration from Automation Variables
   - Storage account and file share names
   - File enumeration progress
   - CSV file creation and upload
   - Cleanup summary

### Step 8: Verify the Audit File

1. Navigate to your **Storage Account** > **File shares**
2. Open your file share
3. Verify the `AuditLifeCycle` folder was created
4. Inside, find the CSV file named `LifeCycleAudit_YYYYMMDD_HHMMSS.csv`
5. Download and review the audit report

### Step 9: Schedule the Runbook (Optional)

1. In the runbook page, click **Schedules** > **+ Add a schedule**
2. Click **Link a schedule to your runbook**
3. Click **+ Add a schedule**
4. Configure the schedule:
   - **Name**: e.g., `Daily-File-Share-Audit`
   - **Starts**: Choose your start date/time
   - **Recurrence**: Select **Recurring**
   - **Recur every**: `1 Day` (or your preferred frequency)
5. Click **Create**
6. **No parameters are needed** - click **OK** to link the schedule
7. The runbook will now execute automatically according to the schedule

## Usage

### Manual Execution

The script reads configuration from Automation Variables - no parameters are required:

1. Navigate to your runbook in Azure Automation
2. Click **Start**
3. Click **OK** (no parameters needed)
4. Monitor the output

The script will automatically:
- Read `StorageAccountName`, `FileShareName`, and `ResourceGroupName` from Automation Variables
- Connect using Managed Identity
- Enumerate files and create the audit CSV
- Upload to the `AuditLifeCycle` folder
- Clean up files older than 31 days

### Scheduled Execution

Once scheduled, the runbook will execute automatically according to your configured schedule, creating timestamped audit files and maintaining the 31-day retention policy.

### Updating Configuration

To change storage account, file share, or resource group:

1. Go to **Shared Resources** > **Variables** in your Automation Account
2. Click on the variable you want to change
3. Update the **Value**
4. Click **Save**

Changes take effect immediately on the next runbook execution.

## Output

The script generates:

- **CSV File**: `LifeCycleAudit_YYYYMMDD_HHMMSS.csv` in the `AuditLifeCycle` folder
- **Console Output**: Detailed execution logs in the runbook output

### Sample CSV Output

```csv
FileName,FullPath,Directory,SizeBytes,SizeKB,SizeMB,LastModified,ETag,ContentType,IsServerEncrypted,FileId,ParentId,AuditDate,StorageAccountName,FileShareName
document.pdf,reports/document.pdf,reports,2048576,2000,1.95,2025-12-01 10:30:00,"""0x8DC...""",application/pdf,True,12345,67890,2025-12-04 14:22:15,mystorageaccount,myfileshare
```

## Retention Policy

The script automatically:
- Keeps audit files for the **last 31 days**
- Deletes audit files older than 31 days during each execution
- Logs the number of files deleted

## Troubleshooting

### Common Issues

**Issue**: "Failed to connect to Azure"
- **Solution**: Verify Managed Identity is enabled in the Automation Account

**Issue**: "Failed to retrieve Automation Variables"
- **Solution**: Ensure all required variables are created in **Shared Resources** > **Variables**:
  - `StorageAccountName` (required)
  - `FileShareName` (required)
  - `ResourceGroupName` (optional)
- Check that variable names match exactly (case-sensitive)

**Issue**: "Access denied" or "Forbidden"
- **Solution**: Verify the Managed Identity has the correct role assignment on the Storage Account

**Issue**: "Storage account not found"
- **Solution**: 
  - Ensure the storage account name in the Automation Variable is correct
  - Verify the storage account is accessible from the Automation Account's subscription
  - If not using `ResourceGroupName` variable, ensure the Managed Identity has access to search across the subscription

**Issue**: "Module not found"
- **Solution**: Import/update Az.Storage and Az.Accounts modules in the Automation Account

**Issue**: "Runbook fails with timeout"
- **Solution**: For very large file shares, consider increasing the runbook timeout or optimizing the script

### Viewing Logs

1. Navigate to your runbook in Azure Automation
2. Go to **Resources** > **Jobs**
3. Select a job to view detailed output and errors

## Best Practices

1. **Test in non-production** before deploying to production file shares
2. **Use Automation Variables** for all configuration (already implemented in the script)
3. **Monitor execution time** for large file shares and adjust schedules accordingly
4. **Review audit files regularly** to ensure data is being captured correctly
5. **Set up alerts** for failed runbook executions
6. **Document variable values** in the variable descriptions for future reference
7. **Use encrypted variables** if storing sensitive configuration (though storage account names are typically not sensitive)

## Cost Considerations

- Azure Automation: First 500 minutes/month free, then minimal cost per minute
- Storage: Minimal cost for storing CSV files (typically < 1 MB each)
- File Share access: Standard transaction costs apply

## Security Notes

- Uses **Managed Identity** - no credentials stored in code
- Operates with **least-privilege** access (read-only option available)
- Audit trail maintained through CSV files
- All operations logged in Azure Automation

## Support & Modifications

### Changing Configuration

No script modification needed - simply update the Automation Variables:
1. Go to **Shared Resources** > **Variables**
2. Click on the variable to update
3. Change the value
4. Save

### Modifying the Script

To modify script behavior:
1. Edit the runbook in Azure Automation
2. Save and test your changes
3. Publish the updated version

For extended retention periods, modify line 238:
```powershell
$cutoffDate = (Get-Date).AddDays(-31)  # Change -31 to your desired days
```

## Configuration Summary

Once setup is complete, your Automation Account should have:

| Component | Details |
|-----------|---------|
| **Managed Identity** | System-assigned, enabled |
| **Role Assignment** | Storage File Data SMB Share Contributor on Storage Account |
| **Modules** | Az.Accounts (2.x+), Az.Storage (5.x+) |
| **Variables** | StorageAccountName, FileShareName, ResourceGroupName (optional) |
| **Runbook** | AzureFileShareAudit (PowerShell 7.2) |
| **Schedule** | Optional - configure based on your audit frequency needs |

## Version History

- **v1.1** (2025-12-04): Updated to use Automation Variables
  - Removed hardcoded parameters
  - Configuration managed through Automation Variables
  - Simplified runbook execution (no parameters needed)
  - Enhanced error messages for variable retrieval

- **v1.0** (2025-12-04): Initial release
  - Recursive file enumeration
  - Comprehensive metadata capture
  - 31-day retention policy
  - Managed Identity authentication

---

**Script Author**: Azure Automation Script  
**Last Updated**: December 4, 2025  
**License**: MIT (modify as needed)
