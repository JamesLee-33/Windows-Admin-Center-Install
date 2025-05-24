
# WAC Certificate Automation Script
# Run this script on the machine that will host Windows Admin Center
This PowerShell script automates the process of:

- Generating a Certificate Signing Request (CSR) using SHA256 and a 2048-bit key
- Accepting a signed certificate from a public CA. The .cer file or .crt.
- Installing the certificate into the Windows Admin Center (WAC) certificate store
- Binding the certificate to port 443 for WAC use

## 🔧 Features

- Supports Subject Alternative Names (SANs)
- Uses `certreq` for standards-compliant CSR generation and certificate merging
    -certreq requires the csr file to be bound via certaccept
- Binds WAC to the certificate automatically via `netsh`
- Designed for server administrators managing secure WAC deployments

## 🧪 Requirements

- Windows Server with PowerShell 5+
- Administrator privileges
- Windows Admin Center installed

## 🚀 Usage

1. Open PowerShell **as Administrator**
2. Run the script:

   ```powershell
   .\Generate-WAC-Certificate.ps1
3. Follow the prompts:
    - Enter subject info and SANs
    - Copy and paste the CSR into your public CA (e.g., GoDaddy)
    - Download the .cer file after signing
    - Input the path to the .cer file when prompted
    - The script will install and bind the cert to WAC

