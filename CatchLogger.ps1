param(
    [string]$JobPath,
    [switch]$TestWebhook,
    [switch]$ProcessPending,
    [switch]$OcrOnly,
    [string]$ImagePath
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$store = Join-Path $root 'catches'
[void][IO.Directory]::CreateDirectory($store)
$utf8 = New-Object Text.UTF8Encoding($false)

function Read-Ini([string]$Path) {
    $values = @{}
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            if ($line -match '^\s*([^;#\[=][^=]*)=(.*)$') {
                $values[$matches[1].Trim()] = $matches[2].Trim()
            }
        }
    }
    return $values
}
function Save-Json([string]$Path, $Value) {
    $temporary = $Path + '.' + $PID + '.tmp'
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 10), $utf8)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
function Read-Reward([string]$Path) {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    Add-Type -AssemblyName System.Drawing
    [void][Windows.Storage.StorageFile, Windows.Storage, ContentType=WindowsRuntime]
    [void][Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType=WindowsRuntime]
    [void][Windows.Graphics.Imaging.BitmapDecoder, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
    [void][Windows.Graphics.Imaging.SoftwareBitmap, Windows.Graphics.Imaging, ContentType=WindowsRuntime]
    [void][Windows.Media.Ocr.OcrEngine, Windows.Foundation, ContentType=WindowsRuntime]
    [void][Windows.Media.Ocr.OcrResult, Windows.Foundation, ContentType=WindowsRuntime]
    [void][Windows.Globalization.Language, Windows.Globalization, ContentType=WindowsRuntime]
    $asTask = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and
        $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1
    function Await($Operation, [Type]$ResultType) {
        $task = $asTask.MakeGenericMethod($ResultType).Invoke($null, @($Operation))
        $task.Wait()
        return $task.Result
    }
    # Only the central reward rectangle is captured by the AHK application.
    # Upscaling improves recognition of the game's small serif text.
    $png = [IO.Path]::ChangeExtension($Path, '.png')
    $ocrPath = [IO.Path]::ChangeExtension($Path, '.ocr.png')
    $weightPath = [IO.Path]::ChangeExtension($Path, '.weight.png')
    $source = [Drawing.Image]::FromFile($Path)
    try {
        $scaled = New-Object Drawing.Bitmap ($source.Width*2), ($source.Height*2)
        try {
            $graphics = [Drawing.Graphics]::FromImage($scaled)
            try {
                $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $graphics.DrawImage($source, 0, 0, $scaled.Width, $scaled.Height)
            } finally { $graphics.Dispose() }
            $scaled.Save($png, [Drawing.Imaging.ImageFormat]::Png)
        } finally { $scaled.Dispose() }
        # Exclude the fish icon and turn the reward text into black on white.
        # This keeps small gray weight numerals readable by Windows OCR.
        $left = [int]($source.Width*0.32)
        $top = [int]($source.Height*0.18)
        $width = [int]($source.Width*0.58)
        $height = [int]($source.Height*0.55)
        $textOnly = New-Object Drawing.Bitmap $width, $height
        try {
            for ($y=0; $y -lt $height; $y++) {
                for ($x=0; $x -lt $width; $x++) {
                    $pixel = ([Drawing.Bitmap]$source).GetPixel($left+$x, $top+$y)
                    $bright = $pixel.R*0.3+$pixel.G*0.59+$pixel.B*0.11
                    $color = if ($bright -gt 110) { [Drawing.Color]::Black } else { [Drawing.Color]::White }
                    $textOnly.SetPixel($x, $y, $color)
                }
            }
            $largeText = New-Object Drawing.Bitmap ($width*3), ($height*3)
            try {
                $textGraphics = [Drawing.Graphics]::FromImage($largeText)
                try {
                    $textGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
                    $textGraphics.DrawImage($textOnly, 0, 0, $largeText.Width, $largeText.Height)
                } finally { $textGraphics.Dispose() }
                $largeText.Save($ocrPath, [Drawing.Imaging.ImageFormat]::Png)
            } finally { $largeText.Dispose() }
        } finally { $textOnly.Dispose() }
        $weightTop = [int]($source.Height*0.34)
        $weightHeight = [int]($source.Height*0.16)
        $weightImage = New-Object Drawing.Bitmap ($width*4), ($weightHeight*4)
        try {
            $weightGraphics = [Drawing.Graphics]::FromImage($weightImage)
            try {
                $weightGraphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
                $destination = New-Object Drawing.Rectangle 0, 0, $weightImage.Width, $weightImage.Height
                $weightGraphics.DrawImage($source, $destination, $left, $weightTop, $width, $weightHeight, [Drawing.GraphicsUnit]::Pixel)
            } finally { $weightGraphics.Dispose() }
            $weightImage.Save($weightPath, [Drawing.Imaging.ImageFormat]::Png)
        } finally { $weightImage.Dispose() }
    } finally { $source.Dispose() }
    $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromLanguage((New-Object Windows.Globalization.Language 'en-US'))
    if (-not $engine) { $engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages() }
    if (-not $engine) { throw 'Windows OCR language unavailable' }
    function Recognize-Image([string]$OcrImage) {
        $file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync($OcrImage)) ([Windows.Storage.StorageFile])
        $stream = Await ($file.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType])
        try {
            $decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync($stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
            $bitmap = Await ($decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
            try {
                $result = Await ($engine.RecognizeAsync($bitmap)) ([Windows.Media.Ocr.OcrResult])
                return @($result.Lines | ForEach-Object { $_.Text.Trim() })
            } finally { $bitmap.Dispose() }
        } finally { $stream.Dispose() }
    }
    $lines = @(Recognize-Image $ocrPath)
    $weightLines = @(Recognize-Image $weightPath)
    if ($lines.Count -gt 0 -and $weightLines.Count -gt 0) {
        $lines = @($lines[0]) + $weightLines + @($lines | Select-Object -Skip 1)
    }
    $cardLines = @(Recognize-Image $png)
    return @{ Lines = $lines; CardLines=$cardLines; Text = ($lines -join "`n"); Image = $png }
}
function Parse-Reward([string[]]$Lines, [bool]$EncounterDetected=$false) {
    $text = $Lines -join "`n"
    if ($EncounterDetected -or $text -match "(?i)that's no fish|comes up the line") {
        $title = @($Lines | Where-Object { $_ -match '[A-Za-z]{3}' -and $_.Length -le 100 } | Select-Object -First 1)
        $name = if ($title.Count) { ($title[0] -replace '^[^A-Za-z]+', '').Trim() } else { 'Fishing encounter' }
        return @{Type='Encounter';Name=$name;Weight='';Verified=$true}
    }
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*(\d+(?:[.,]\d+)?)\s*(?:jin|jln|in)\b' -and $i -gt 0) {
            $weight = $matches[1].Replace(',', '.') + ' jin'
            for ($titleIndex=0; $titleIndex -lt $i; $titleIndex++) {
                $candidate = $Lines[$titleIndex]
                if ($candidate -match '^\s*\d' -or $candidate -match '(?i)^(jin|jln|in)$|angler\s+xp') { continue }
                $name = $candidate -replace '^[^A-Za-z]+', ''
                $name = $name -creplace '([a-z])([A-Z])', '$1 $2'
                if ($name.Length -ge 3 -and $name.Length -le 80) {
                    return @{ Type='Fish'; Name=$name.Trim(); Weight=$weight; Verified=$true }
                }
            }
        }
    }
    if ($text -match '(?i)iron.shell snapper|comes up after you|river snapper') {
        return @{ Type='Encounter'; Name='River Snapper'; Weight=''; Verified=$true }
    }
    if ($text -match '(?i)\+?\d+\s+(?:angler\s+xp|angleo)' -and $Lines.Count -gt 1) {
        $name = $Lines[0] -replace '^[^A-Za-z]+', ''
        if ($name.Length -ge 3 -and $name.Length -le 80 -and $name -notmatch '(?i)angler\s+xp') {
            return @{Type='Catch';Name=$name.Trim();Weight='Not read';Verified=$true}
        }
    }
    # Do not turn arbitrary world text or a failed reel into a named catch.
    return @{ Type='Unreadable'; Name='Reward not confidently read'; Weight=''; Verified=$false }
}
function Update-History {
    $records = @(Get-ChildItem -LiteralPath $store -Filter '*.json' | ForEach-Object {
        try { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json } catch { }
    } | Sort-Object TimestampUtc, Id)
    $rows = New-Object 'Collections.Generic.List[string]'
    $rows.Add("Time`tName`tWeight`tType`tDiscord`tReelSeconds`tId")
    foreach ($record in $records) {
        $fields = @($record.LocalTime, $record.Name, $record.Weight, $record.Type,
            $record.DiscordStatus, $record.ReelSeconds, $record.Id)
        $rows.Add((($fields | ForEach-Object { ([string]$_) -replace '[\t\r\n]', ' ' }) -join "`t"))
    }
    $temporary = Join-Path $root ('CatchHistory.' + $PID + '.tmp')
    [IO.File]::WriteAllLines($temporary, $rows, $utf8)
    Move-Item -LiteralPath $temporary -Destination (Join-Path $root 'CatchHistory.tsv') -Force
}
function Send-Discord($Record, [string]$Picture = '') {
    $configuration = Read-Ini (Join-Path $root 'Fishing.secrets.ini')
    $url = $configuration['WebhookURL']
    if (-not $url) { return @{ Status='Disabled'; MessageId='' } }
    if ($url -notmatch '^https://discord\.com/api/webhooks/\d+/[A-Za-z0-9_-]+$') {
        return @{ Status='Invalid webhook configuration'; MessageId='' }
    }
    Add-Type -AssemblyName System.Net.Http
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $fields = @(@{name='Caught at';value=[string]$Record.LocalTime;inline=$true})
    if ($Record.Weight) { $fields += @{name='Weight';value=[string]$Record.Weight;inline=$true} }
    if ($Record.ReelSeconds -gt 0) { $fields += @{name='Reel time';value=([string]$Record.ReelSeconds+' s');inline=$true} }
    $embed = @{ title=([string]$Record.Name); color=5763719; fields=$fields;
        footer=@{text=('Fishing Assistant | '+$Record.Id)}; timestamp=$Record.TimestampUtc }
    if ($Record.Type -eq 'Encounter') { $embed.color=15158332; $embed.description='A fishing mob encounter was detected.' }
    if ($Record.Type -eq 'Test') { $embed.description='Webhook connection test. This is not a catch.' }
    if ($Record.Type -eq 'Unreadable') { $embed.description='A reel ended, but its reward could not be read confidently. Check the local history image.' }
    $attach = $Picture -and $Record.Verified -and (Test-Path -LiteralPath $Picture)
    if ($attach) { $embed.image=@{url='attachment://reward.png'} }
    $payload = @{username='Fishing Assistant'; allowed_mentions=@{parse=@()}; embeds=@($embed)} | ConvertTo-Json -Depth 8 -Compress
    $client = New-Object Net.Http.HttpClient
    $client.Timeout = [TimeSpan]::FromSeconds(12)
    try {
        for ($attempt=0; $attempt -lt 3; $attempt++) {
            $multipart = New-Object Net.Http.MultipartFormDataContent
            try {
                $json = New-Object Net.Http.StringContent $payload, ([Text.Encoding]::UTF8), 'application/json'
                $multipart.Add($json, 'payload_json')
                if ($attach) {
                    $binary = New-Object Net.Http.ByteArrayContent (,[IO.File]::ReadAllBytes($Picture))
                    $binary.Headers.ContentType = New-Object Net.Http.Headers.MediaTypeHeaderValue 'image/png'
                    $multipart.Add($binary, 'files[0]', 'reward.png')
                }
                try { $response = $client.PostAsync(($url+'?wait=true'), $multipart).GetAwaiter().GetResult() }
                catch { return @{Status='Network error (delivery unconfirmed)';MessageId=''} }
                try {
                    $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
                    if ($response.IsSuccessStatusCode) {
                        $sent = $content | ConvertFrom-Json
                        return @{Status='Sent';MessageId=[string]$sent.id}
                    }
                    if ([int]$response.StatusCode -eq 429 -and $attempt -lt 2) {
                        $delay = 2
                        try { $delay = [Math]::Min(30, [Math]::Max(1, ($content | ConvertFrom-Json).retry_after)) } catch { }
                        Start-Sleep -Milliseconds ([int]($delay*1000))
                        continue
                    }
                    return @{Status=('HTTP '+[int]$response.StatusCode);MessageId=''}
                } finally { $response.Dispose() }
            } finally { $multipart.Dispose() }
        }
    } finally { $client.Dispose() }
    return @{Status='Rate limited';MessageId=''}
}

$mutex = $null
$locked = $false
$stage = 'initialize'
try {
    if ($ProcessPending) {
        foreach ($pendingJob in (Get-ChildItem -LiteralPath $store -Filter '*.ini' | Sort-Object Name)) {
            $pendingRecord = Join-Path $store ($pendingJob.BaseName+'.json')
            if (-not (Test-Path -LiteralPath $pendingRecord)) {
                & (Join-Path $PSHOME 'powershell.exe') -NoLogo -NoProfile -File $PSCommandPath -JobPath $pendingJob.FullName
            }
        }
        exit 0
    }
    if ($OcrOnly) {
        $reward = Read-Reward $ImagePath
        $cardText = $reward.CardLines -join ' '
        $parsed = if ($cardText -match "(?i)that's no fish|comes up the line|comes up after you") {
            Parse-Reward $reward.CardLines $true
        } else { Parse-Reward $reward.Lines }
        @{Ocr=$reward.Text; CardOcr=($reward.CardLines -join "`n"); Parsed=$parsed} | ConvertTo-Json -Depth 4
        exit 0
    }
    if ($TestWebhook) {
        $test = @{Id=('test-'+[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()); Type='Test'; Name='Catch history connected';
            LocalTime=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); TimestampUtc=[DateTime]::UtcNow.ToString('o');
            Weight=''; ReelSeconds=0; Verified=$false}
        $status = Send-Discord $test
        Write-Output ('Webhook test: '+$status.Status)
        if ($status.Status -ne 'Sent') { exit 1 }
        exit 0
    }
    if (-not $JobPath) { throw 'JobPath required' }
    $job = Read-Ini $JobPath
    if ($job['Id'] -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid job identifier' }
    $recordPath = Join-Path $store ($job['Id']+'.json')
    # Serialize workers so history projections and webhook ordering stay consistent.
    $mutex = New-Object Threading.Mutex($false, 'Local\FishingAssistantCatchLogger')
    $locked = $mutex.WaitOne(120000)
    if (-not $locked) { throw 'History worker busy' }
    if (Test-Path -LiteralPath $recordPath) {
        # A persisted event is never reposted automatically after an ambiguous send.
        exit 0
    }
    $stage = 'OCR'
    try {
        $reward = Read-Reward $job['ImagePath']
        $cardText = $reward.CardLines -join ' '
        if ($job['EncounterDetected'] -eq '1' -or $cardText -match "(?i)that's no fish|comes up the line|comes up after you") {
            $parsed = Parse-Reward $reward.CardLines $true
        } else {
            $parsed = Parse-Reward $reward.Lines
        }
    } catch {
        $reward = @{Image=$job['ImagePath'];Text='OCR unavailable ('+$_.Exception.GetType().Name+')'}
        $parsed = @{Type='Unreadable';Name='Reward not confidently read';Weight='';Verified=$false}
    }
    $record = [ordered]@{Id=$job['Id'];TimestampUtc=$job['TimestampUtc'];LocalTime=$job['LocalTime'];
        Type=$parsed.Type;Name=$parsed.Name;Weight=$parsed.Weight;Verified=$parsed.Verified;
        ReelSeconds=[double]::Parse($job['ReelSeconds'], [Globalization.CultureInfo]::InvariantCulture);
        Image=$reward.Image;Ocr=$reward.Text;DiscordStatus='Pending';DiscordMessageId=''}
    # Save local history before attempting any network request.
    Save-Json $recordPath $record
    Update-History
    $stage = 'Discord'
    $sendImage = if ($job['IncludeImage'] -eq '0') { '' } else { $reward.Image }
    $delivery = Send-Discord $record $sendImage
    $record.DiscordStatus = $delivery.Status
    $record.DiscordMessageId = $delivery.MessageId
    Save-Json $recordPath $record
    Update-History
} catch {
    # Never log raw HTTP exceptions, which may contain the secret webhook URL.
    $safeError = 'Catch logger error during '+$stage+' ('+$_.Exception.GetType().Name+')'
    [IO.File]::AppendAllText((Join-Path $root 'CatchLogger.log'), ((Get-Date -Format 's')+' | '+$safeError+"`r`n"), $utf8)
    Write-Error $safeError
    exit 1
} finally {
    if ($locked -and $mutex) { $mutex.ReleaseMutex() }
    if ($mutex) { $mutex.Dispose() }
}
