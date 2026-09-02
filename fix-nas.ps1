# fix_nas.ps1

# 1. Enable Network Discovery + File Sharing
Set-NetFirewallRule -DisplayGroup "Network Discovery" -Enabled True -Profile Private -ErrorAction SilentlyContinue
Set-NetFirewallRule -DisplayGroup "File and Printer Sharing" -Enabled True -Profile Private -ErrorAction SilentlyContinue
Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue

# 2. Enable insecure guest logons for Home edition NAS (most NAS need this)
Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" -Name "AllowInsecureGuestAuth" -Value 1 -Type DWord -Force

# 3. Check if NAS online
Test-Connection 192.168.1.100 -Count 2

# 4. Remove old broken Z: mapping
net use Z: /delete /y 2>$null

# 5. Map again - will prompt for user/pass if needed
# If your NAS has no password, use guest. If it has user, replace:
$nasUser = "admin" # CHANGE to your NAS username, or keep as is for guest
$nasPass = Read-Host "Enter NAS password for $nasUser (leave empty for guest)" -AsSecureString
$plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($nasPass))

if ([string]::IsNullOrWhiteSpace($plain)) {
    net use Z: \\192.168.1.100\smbdata /persistent:yes
} else {
    # Save credential for reboot
    cmdkey /add:192.168.1.100 /user:$nasUser /pass:$plain
    net use Z: \\192.168.1.100\smbdata /persistent:yes /user:$nasUser $plain
}

# 6. Verify
Get-PSDrive Z
dir Z:\ | Select-Object -First 10
