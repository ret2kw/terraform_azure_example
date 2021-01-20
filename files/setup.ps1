Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))

refreshenv
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") 

choco feature enable -n allowGlobalConfirmation
choco install openssl -y
choco install powershell-core -y

refreshenv
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User") 


$cert=@'
${cert}
'@

$privkey=@'
${privkey}
'@

$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
[System.IO.File]::WriteAllLines("C:\terraform\priv.key", $privkey, $Utf8NoBomEncoding) 
[System.IO.File]::WriteAllLines("C:\terraform\cert.cer", $cert, $Utf8NoBomEncoding) 

openssl pkcs12 -export -out C:\terraform\certificate.pfx -inkey C:\terraform\priv.key -in C:\terraform\cert.cer -passout pass:${pfxpass}

$pfxpass = ConvertTo-SecureString "${pfxpass}" -AsPlainText -Force

Import-PfxCertificate -FilePath C:\terraform\certificate.pfx -CertStoreLocation Cert:\LocalMachine\My -Password $pfxpass

Remove-Item -Path C:\terraform\priv.key
Remove-Item -Path C:\terraform\certificate.pfx


# Install the OpenSSH Client
Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0

# Install the OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

Start-Service sshd
Set-Service -Name sshd -StartupType 'Automatic'

#set default shell to powershell-core
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" -Name DefaultShell -Value "C:\Program Files\PowerShell\7\pwsh.exe" -PropertyType String -Force

$sshd_config=@'
${sshd_config}
'@

[System.IO.File]::WriteAllLines("C:\ProgramData\ssh\sshd_config", $sshd_config, $Utf8NoBomEncoding)

Restart-Service sshd


$profiles = Get-NetConnectionProfile
Foreach ($i in $profiles) {
    Write-Host ("Updating Interface ID {0} to be Private.." -f $profiles.InterfaceIndex)
    Set-NetConnectionProfile -InterfaceIndex $profiles.InterfaceIndex -NetworkCategory Private
}

Write-Host "Obtaining the Thumbprint of the Certificate from KeyVault"
$Thumbprint = (Get-ChildItem -Path Cert:\LocalMachine\My | Where-Object {$_.Subject -match "example.com"}).Thumbprint

Write-Host "Enable HTTPS in WinRM.."
winrm create winrm/config/Listener?Address=*+Transport=HTTPS "@{Hostname=`"example.com`"; CertificateThumbprint=`"$Thumbprint`"; Port=`"${winrm_port}`"}"

Write-Host "Enabling Basic Authentication.."
winrm set winrm/config/service/Auth "@{Basic=`"true`"}"

Write-Host "Re-starting the WinRM Service"
net stop winrm
net start winrm

Write-Host "Open Firewall Ports"
netsh advfirewall firewall add rule name="Windows Remote Management (HTTPS-In)" dir=in action=allow protocol=TCP localport=${winrm_port}

netsh advfirewall firewall add rule name="Remote Desktop port" dir=in action=allow protocol=TCP localport=${rdp_port}

netsh advfirewall firewall add rule name="OpenSSH Port" dir=in action=allow protocol=TCP localport=${sshd_port}

$NewPort = ${rdp_port}

$RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
$KeyName ="PortNumber"

try {
    Set-ItemProperty -Path $RegistryPath -Name $KeyName -Value $NewPort -Force | Out-Null
}
catch {
    Write-Host "Error. Please check or contact your administrator" -ForegroundColor Red
}

# restart RDP service
Get-Service -ComputerName . -Name 'Remote Desktop Services UserMode Port Redirector' | Stop-Service -Force -Verbose
Get-Service -ComputerName . -Name 'TermService' | Stop-Service -Force -Verbose
Get-Service -ComputerName . -Name 'TermService' | Start-Service -Verbose
Get-Service -ComputerName . -Name 'Remote Desktop Services UserMode Port Redirector' | Start-Service -Verbose


${stager}


