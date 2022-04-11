# https://docs.ansible.com/ansible/latest/user_guide/windows_winrm.html

# global
$output_path = "C:\Users\me\Documents\"
# pre

function Generate-Certificate-SSL {
  # Set the name of the local user that will have the key mapped to
  USERNAME="me"

  cat > openssl.conf << EOL
  distinguished_name = req_distinguished_name
  [req_distinguished_name]
  [v3_req_client]
  extendedKeyUsage = clientAuth
  subjectAltName = otherName:1.3.6.1.4.1.311.20.2.3;UTF8:$USERNAME@localhost
  EOL

  export OPENSSL_CONF=openssl.conf
  openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -out cert.pem -outform PEM -keyout cert_key.pem -subj "/CN=$USERNAME" -extensions v3_req_client
  rm openssl.conf
}

function Generate-Certificate-SelfSigned {
  # Set the name of the local user that will have the key mapped
  $username = "me"
  $output_path = "C:\Users\me\Documents\"

  # Instead of generating a file, the cert will be added to the personal
  # LocalComputer folder in the certificate store
  $cert = New-SelfSignedCertificate -Type Custom `
      -Subject "CN=$username" `
      -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2","2.5.29.17={text}upn=$username@localhost") `
      -KeyUsage DigitalSignature,KeyEncipherment `
      -KeyAlgorithm RSA `
      -KeyLength 2048

  # Export the public key
  $pem_output = @()
  $pem_output += "-----BEGIN CERTIFICATE-----"
  $pem_output += [System.Convert]::ToBase64String($cert.RawData) -replace ".{64}", "$&`n"
  $pem_output += "-----END CERTIFICATE-----"
  [System.IO.File]::WriteAllLines("$output_path\cert.pem", $pem_output)

  # Export the private key in a PFX file
  [System.IO.File]::WriteAllBytes("$output_path\cert.pfx", $cert.Export("Pfx"))
}

function Import-to-Certificate-Store{
  $cert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2
  $cert.Import("$output_path\cert.pem")

  $store_name = [System.Security.Cryptography.X509Certificates.StoreName]::Root
  $store_location = [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
  $store = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $store_name, $store_location
  $store.Open("MaxAllowed")
  $store.Add($cert)
  $store.Close()
}

function Import-certificate-public-key {
  $cert = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2
  $cert.Import("$output_path\cert.pem")

  $store_name = [System.Security.Cryptography.X509Certificates.StoreName]::TrustedPeople
  $store_location = [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine
  $store = New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Store -ArgumentList $store_name, $store_location
  $store.Open("MaxAllowed")
  $store.Add($cert)
  $store.Close()
}

# https://docs.ansible.com/ansible/latest/user_guide/windows_winrm.html#mapping-a-certificate-to-an-account

function Mapping-Certificate-to-Account {
  $username = "me"
  $password = ConvertTo-SecureString -String "password" -AsPlainText -Force
  $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $username, $password

  # This is the issuer thumbprint which in the case of a self generated cert
  # is the public key thumbprint, additional logic may be required for other
  # scenarios
  $thumbprint = (Get-ChildItem -Path cert:\LocalMachine\root | Where-Object { $_.Subject -eq "CN=$username" }).Thumbprint

  New-Item -Path WSMan:\localhost\ClientCertificate `
      -Subject "$username@localhost" `
      -URI * `
      -Issuer $thumbprint `
      -Credential $credential `
      -Force
}
