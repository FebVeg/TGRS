
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
    if ($output.Length -gt 4096)    # If the output incoming string is greater than 4096 chars
    {
        Write-Host "Separation for every 4096 characters of the input output..."
    }

    $output_splitted        = $output -split ""             # Split every character from the incoming output
    $temp_part_of_output    = ""                            # Set a temporary block for save chars into it
    $array_of_output_parts  = @()                           # Set an array that it will used for saving multipart strings
    $counter                = 0                             # Set a counter to 0

    Write-Host "Working on it..."

    foreach ($char in $output_splitted)                     # For every character inside the incoming output
    {
        if ($counter -eq 4096)                              # If the counter used to verify the cycle has exceeded 4096 times the job
        {
            Write-Host "Creating a block..."
            $array_of_output_parts += $temp_part_of_output  # Pass to the array the block
            Write-Host "Block created..."
            $temp_part_of_output = ""                       # Clears the temporary variable used to insert the selected characters
            $counter = 0                                    # Set the counter to 0
        }

        $temp_part_of_output += $char                       # Pass into the temporary variable the character
        $counter += 1
    }
    
    Write-Host "Create the last block..."
    $array_of_output_parts += $temp_part_of_output          # Add to the array the last block not handled because not greater than 4096 chars
    
    Write-Host "The output is ready to be sent"
    return $array_of_output_parts                           # return a string object
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
        Write-Host -ForegroundColor RED -BackgroundColor Black $Error[0]    # Its just for debug 
        $wait = $wait + 100                                                 # Increase by 100ms the wait timer
        Start-Sleep -Milliseconds $wait                                     # Waiting $wait seconds
    }
}


function commandListener 
# The "commandListener" function establishes a connection to the Telegram API waiting for a new message from the controller of the Bot. 
# Once the controller of the Bot sends a message, it is interpreted as a command to be executed on the Bot's powershell. 
# Once the command is executed, the result of the command will then be sent as a reply to the message to the controller of the Bot.
# Attention! There is a timer that will be incremented to 100ms at a time to limit HTTPS requests to the Telegram API.
{
    if (-Not(Test-Path -Path $cache_file))                                              # If the cache file doesn't exists creating it
    {
        Add-Content -Path $cache_file -Value "0" -Force                                 # Add a '0' to the cache file
    }

    try 
    {
        $_ip    = (Invoke-WebRequest -Uri "https://ident.me/").Content                  # Get the Public IP from the ISP
        $_path  = (Get-Location).Path                                                   # Get the current location of the Bot
        $_user  = checkAdminRights                                                      # Get the boolean value to check if the user is an administrator or not
        $_host  = $env:COMPUTERNAME                                                     # Get the current Hostname or the name of the machine
        $_body  = '{0} ({1}) - IP: {2} - [{3}]' -f $_host, $_user, $_ip, $_path         # Build everything...
        sendMessage $_body                                                              # Send a message with the body

        while (Invoke-RestMethod -Method Get "api.telegram.org")                        # As long as the telegram url is reachable
        {
            $message    = Invoke-RestMethod -Method Get -Uri $api_get_updates           # Get the JSON response about the telegram updates
            $message    = $message.result.Message[-1]                                   # Get the last JSON record
            $message_id = $message.message_id                                           # Get the message_id of the update
            $user_id    = $message.chat.id                                              # Get the ID about the sender message
            $text       = $message.text                                                 # Get the text message (it will be the command that you want to execute)
            $document   = $message.document                                             # If there is a document value inside the JSON record save it to this variable

            if ((Get-Content -Path $cache_file)[-1] -notmatch $message_id)              # Check if the last record of the cache file is not the message_id (this prevent multi-executions)
            {
                Write-Host ($tID + " of the verified message: " + $message_id)
                Add-Content -Path $cache_file -Value $message_id -Force                 # Put in the cache file the message_id for saving it
                if ($user_id -match $tID)                                       # Check if the sender ID is your Telegram ID
                {
                    Write-Host ("Username verified: " + $username)
                    if ($text -match "exit")                                            # If the message is "exit" than close the powershell session
                    {
                        Write-Host "Connection closure..."
                        exit
                    }

                    if (Test-Path -Path $text)                                          # If the message is a filepath then send the document to telegram
                    {
                        sendDocument $text                                              # Send the document
                    } 
                    elseif ($text.Length -gt 0)                                         # If the length of message is greater 0 then execute it
                    {
                        try {
                            $output = Invoke-Expression $text | Out-String              # Execute the message and save it as a string
                        } catch {
                            $output = $Error[0] | Out-String                            # If the command returns error save it as a string
                        }
                        
                        $output = splitOutput $output                                   # Create an output container for more than 4096 characters
                        
                        foreach ($block in $output)                                     # For each block of 4096 characters, send them to telegram as a message
                        {
                            $block = $block | Out-String
                            if ($block.Length -gt 2)                                    # If a block is greater 2 send it 
                            {
                                sendMessage $block $message_id                          # Send a block as an answer for the incoming text message
                            } 
                            else {
                                sendMessage "No Output Data" $message_id                # If the block is 2 about length answer it 
                            }
                        }
                        
                        $wait = 1000                                                    # Set a sleep timer to 1000
                    }
                    
                    if ($document)                                                      # If there is a document in the message download it
                    {
                        $file_id   = $document.file_id                                  # Get the file_id of the document
                        $file_name = $document.$file_name                               # Get the file_name of the document
                        downloadDocument $file_id $file_name                            # Download this document
                    }
                } 
                else {
                    sendMessage ("Unauthorized user found! " + $user_id)                # If an unauthorized user try to use bot then alert the controller
                }
            }

            if ($wait -eq 15000)                                                        # If the waiting timer is 15000ms then restore ti 1000
            {
                $wait = 1000                                                            # Restore the timer to 1000ms
            } else {                                                                    # If timer is not 15000ms then increase it by 100ms
                $wait = $wait + 100                                                     # Increase the sleep timer by 100ms
            }

            Start-Sleep -Milliseconds $wait                                             # Sleep timer
        }
    } catch {
        while (-Not(tnc).PingSucceeded)                                                 # If the connection lost wait until connected
        { 
            Start-Sleep -Milliseconds $wait                                             # Use a sleep timer for relaxing the CPU
            $wait = $wait + 100                                                         # Increasing the sleep timer by 100ms
        }

        commandListener                                                                 # Once the connection will be restored reset the listener
    }
}


commandListener # Start the Bot