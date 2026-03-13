if ($env:MSI_SECRET) {
   Disable-AzContextAutosave -Scope Process | Out-Null
   Connect-AzAccount -Identity -AccountId $env:AZURE_CLIENT_ID
}