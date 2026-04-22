# SQL Convert Tool - Read from clipboard, write back to clipboard
# Modes: convert | reverse | to-append | to-concat
param(
    [string]$Mode    = 'convert',
    [string]$JavaVar = 'sbSql'
)

$text = Get-Clipboard -Raw
if (-not $text -or $text.Trim() -eq '') {
    Write-Host 'No clipboard content. Please copy SQL first.' -ForegroundColor Yellow
    exit 1
}

# Java string concat "..." + "..." -> plain SQL
function ConvertJavaConcat([string]$t) {
    $dq = [char]34
    $lines = $t -split "`n"
    $parts = [System.Collections.Generic.List[string]]::new()
    $matchCount = 0
    foreach ($line in $lines) {
        $s = $line.Trim()
        if (-not $s) { continue }
        $tmp = if ($s[0] -eq '+') { $s.Substring(1).TrimStart() } else { $s }
        if ($tmp -match '^[A-Za-z_]\w*(?:\s+[A-Za-z_]\w*)?\s*=\s*') {
            $tmp = $tmp.Substring($Matches[0].Length)
        }
        if ($tmp.Length -gt 0 -and $tmp[0] -eq $dq) {
            $e = $tmp.TrimEnd()
            if ($e[-1] -eq ';' -or $e[-1] -eq '+') { $e = $e.Substring(0, $e.Length - 1).TrimEnd() }
            if ($e[-1] -eq $dq -and $e.Length -ge 2) {
                $parts.Add($e.Substring(1, $e.Length - 2))
                $matchCount++
                continue
            }
        }
        $parts.Add($line)
    }
    if ($matchCount -eq 0) { return $t }
    return $parts -join "`n"
}

# sbSql.append("..."); -> plain SQL
function ConvertJavaAppend([string]$t) {
    if ($t -notmatch 'sbSql\.append') { return $t }
    $dq = [char]34
    $bs = [char]92
    $lines = $t -split "`n"
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $s = $line.Trim()
        if ($s -match '^sbSql\.append\s*\(') {
            $start = $s.IndexOf('(')
            $end   = $s.LastIndexOf(')')
            if ($start -ge 0 -and $end -gt $start) {
                $inner = $s.Substring($start + 1, $end - $start - 1).Trim()
                $sb  = [System.Text.StringBuilder]::new()
                $pos = 0
                while ($pos -lt $inner.Length) {
                    if ($inner[$pos] -eq $dq) {
                        $e2 = $pos + 1
                        while ($e2 -lt $inner.Length -and $inner[$e2] -ne $dq) {
                            if ($inner[$e2] -eq $bs) { $e2++ }
                            $e2++
                        }
                        if ($e2 -gt $pos + 1) { [void]$sb.Append($inner.Substring($pos + 1, $e2 - $pos - 1)) }
                        $pos = $e2 + 1
                    } elseif ($inner.Substring($pos) -match '^\s*\+\s*([A-Za-z_]\w*)\s*') {
                        [void]$sb.Append('{?' + $Matches[1] + '}')
                        $pos += $Matches[0].Length
                    } else { $pos++ }
                }
                $parts.Add($sb.ToString())
            } else { $parts.Add($line) }
        } elseif ($s) { $parts.Add($line) }
    }
    return $parts -join "`n"
}

$result = $text
switch ($Mode) {
    'convert' {
        $result = ConvertJavaConcat $result
        $result = ConvertJavaAppend $result
        $result = [regex]::Replace($result, '\{[?](\w+)\}', ':$1')
        $result = [regex]::Replace($result, '\bIN_[A-Z][A-Z0-9_]+\b', ':$0')
    }
    'reverse' {
        $result = [regex]::Replace($result, ':(IN_[A-Z][A-Z0-9_]+)', '$1')
        $result = [regex]::Replace($result, ':([A-Za-z_]\w*)', '{?$1}')
    }
    'to-append' {
        $lines = ($result -split "`n") | Where-Object { $_.Trim() -ne '' }
        $result = ($lines | ForEach-Object { "$JavaVar.append(`" $($_.Trim()) `");" }) -join "`n"
    }
    'to-concat' {
        $lines = ($result -split "`n") | Where-Object { $_.Trim() -ne '' }
        if ($lines.Count -eq 0) { break }
        $out = [System.Collections.Generic.List[string]]::new()
        $out.Add("String $JavaVar = `" $($lines[0].Trim()) `"")
        for ($i = 1; $i -lt $lines.Count; $i++) { $out.Add("    + `" $($lines[$i].Trim()) `"") }
        $result = ($out -join "`n") + ';'
    }
}

$result = if ($result) { $result.Trim() } else { '' }
Set-Clipboard -Value $result
Write-Host "Done ($Mode) - copied to clipboard. Press Ctrl+V to paste." -ForegroundColor Green
