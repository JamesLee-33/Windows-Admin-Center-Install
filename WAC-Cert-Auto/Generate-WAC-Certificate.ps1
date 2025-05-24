## PowerShell Script to generate a Certificate Signing Request (CSR) using SHA256 and a 2048-bit key size,
## then merge the signed cert from a public CA into the WAC certificate store, and bind it for use.
##
## Author: James Lee
## Version: v1.3
## Description: Generates CSR, supports SANs, accepts signed cert, merges, and configures WAC.
##

####################
# Prerequisite check
####################
if (-NOT([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Administrator privileges are required. Please restart this script with elevated rights." -ForegroundColor Red
    Pause
    Throw "Administrator privileges are required. Please restart this script with elevated rights."
}

#######################
# Setting the variables
#######################
$UID = [guid]::NewGuid()
$files = @{
    'settings' = "$($env:TEMP)\$($UID)-settings.inf"
    'csr'      = "$($env:TEMP)\$($UID)-csr.req"
}

$request = @{ SAN = @{} }

Write-Host "Provide the Subject details required for the Certificate Signing Request" -ForegroundColor Yellow
$request['CN'] = Read-Host "Common Name (CN)"
$request['O']  = Read-Host "Organisation (O)"
$request['OU'] = Read-Host "Organisational Unit (OU)"
$request['L']  = Read-Host "Locality / City (L)"
$request['S']  = Read-Host "State (S)"
$request['C']  = Read-Host "Country Code (C)"

###########################
# Subject Alternative Names
###########################
$i = 0
while ($true) {
    $i++
    $sanInput = Read-Host "Subject Alternative Name $i (e.g. alt.company.com / leave empty to finish)"
    if ([string]::IsNullOrWhiteSpace($sanInput)) {
        break
    }
    $request['SAN'][$i] = $sanInput
}

#########################
# Create the settings.inf
#########################
$settingsInf = @"
[Version]
Signature=`"$Windows NT$`

[NewRequest]
KeyLength = 2048
Exportable = TRUE
MachineKeySet = TRUE
SMIME = FALSE
RequestType = PKCS10
ProviderName = "Microsoft RSA SChannel Cryptographic Provider"
ProviderType = 12
HashAlgorithm = sha256
Subject = "CN={{CN}},OU={{OU}},O={{O}},L={{L}},S={{S}},C={{C}}"

[Extensions]
{{SAN}}
"@

$request['SAN_string'] = & {
    if ($request['SAN'].Count -gt 0) {
        $san = '2.5.29.17 = "{text}"' + "`r`n"
        foreach ($sanItem in $request['SAN'].Values) {
            $san += '_continue_ = "dns=' + $sanItem + '&"' + "`r`n"
        }
        return $san
    }
    return ""
}

$settingsInf = $settingsInf.Replace("{{CN}}", $request['CN']).Replace("{{O}}", $request['O']).Replace("{{OU}}", $request['OU']).Replace("{{L}}", $request['L']).Replace("{{S}}", $request['S']).Replace("{{C}}", $request['C']).Replace("{{SAN}}", $request['SAN_string'])

$settingsInf | Set-Content -Path $files['settings']

#################################
# Show INF File for Debugging
#################################
Write-Host "`nGenerated INF File:`n" -ForegroundColor Cyan
Get-Content $files['settings'] | Write-Output

#################################
# Create CSR
#################################
Write-Host "`nGenerating CSR..." -ForegroundColor Cyan
certreq -new $files['settings'] $files['csr'] > $null

$CSR = Get-Content $files['csr']
Write-Host "`nCSR generated:`n" -ForegroundColor Green
Write-Output $CSR

Write-Host "`nCopy CSR to clipboard? (y|n): " -ForegroundColor Yellow -NoNewline
if ((Read-Host) -ieq "y") {
    $CSR | clip
    Write-Host "✅ CSR copied to clipboard. Paste it at your CA." -ForegroundColor Green
}

########################
# Remove temporary files
########################
$files.Values | ForEach-Object {
    Remove-Item $_ -ErrorAction SilentlyContinue
}

############################
# Wait for Public Certificate
############################
Write-Host "`nAfter submitting the CSR to your CA, save the signed cert (e.g., C:\temp\wac-signed.cer)." -ForegroundColor Yellow
$certPath = Read-Host "Enter the full path to your signed certificate file"

if (-Not (Test-Path $certPath)) {
    Write-Host "❌ The file $certPath was not found. Exiting." -ForegroundColor Red
    exit 1
}

###################################
# Accept the cert and merge with key
###################################
try {
    Write-Host "`nMerging signed certificate into LocalMachine\My store..." -ForegroundColor Yellow
    certreq -accept $certPath
    Write-Host "✅ Certificate successfully installed to Cert:\LocalMachine\My" -ForegroundColor Green
} catch {
    Write-Host "❌ Failed to install certificate: $_" -ForegroundColor Red
    exit 1
}

###################################
# Bind to Windows Admin Center (port 443)
###################################
$cert = Get-ChildItem Cert:\LocalMachine\My | Where-Object {
    $_.Subject -like "*CN=$($request['CN'])*" -and $_.HasPrivateKey
} | Sort-Object NotBefore -Descending | Select-Object -First 1

if (-not $cert) {
    Write-Host "❌ No matching cert with private key found. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "`nBinding cert to Windows Admin Center (port 443)..." -ForegroundColor Yellow
Stop-Service ServerManagementGateway -ErrorAction SilentlyContinue

netsh http delete sslcert ipport=0.0.0.0:443 > $null 2>&1
netsh http add sslcert ipport=0.0.0.0:443 certhash=$($cert.Thumbprint) appid='{00112233-4455-6677-8899-AABBCCDDEEFF}' > $null

Start-Service ServerManagementGateway

Write-Host "✅ WAC is now using the new certificate." -ForegroundColor Green
