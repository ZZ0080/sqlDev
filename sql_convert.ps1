# SQL 參數清理工具 - 命令列版本
# 使用方式：從剪貼簿讀取 SQL，轉換後寫回剪貼簿
#
# 模式 (Mode):
#   convert   : 報表/Java 格式 → 可執行 SQL（預設）
#   reverse   : :param → {?param}，:IN_XXX → IN_XXX
#   to-append : 純 SQL → sbSql.append("..."); 格式
#   to-concat : 純 SQL → String var = "..." + "..." 格式

param(
    [string]$Mode     = "convert",
    [string]$JavaVar  = "sbSql"
)

# ── 讀取剪貼簿 ────────────────────────────────────────────
$text = Get-Clipboard -Raw
if (-not $text -or $text.Trim() -eq '') {
    Write-Host "⚠ 剪貼簿無內容，請先複製 SQL。" -ForegroundColor Yellow
    exit 1
}

# ── 函式：Java 字串拼接 "..." + "..." → 純 SQL ───────────
function ConvertJavaConcat([string]$t) {
    $lines = $t -split "`n"
    $pattern = '^(?:[^"=]*=\s*)?(?:\+\s*)?"(.*?)"\s*(?:[+;]\s*)?$'
    $hasMatch = $false
    foreach ($line in $lines) {
        if ($line.Trim() -match $pattern) { $hasMatch = $true; break }
    }
    if (-not $hasMatch) { return $t }

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $stripped = $line.Trim()
        if (-not $stripped) { continue }
        if ($stripped -match $pattern) {
            $parts.Add($Matches[1])
        } else {
            $parts.Add($line)
        }
    }
    return $parts -join "`n"
}

# ── 函式：sbSql.append("..."); → 純 SQL ──────────────────
function ConvertJavaAppend([string]$t) {
    if ($t -notmatch 'sbSql\.append\s*\(') { return $t }

    $lines = $t -split "`n"
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $lines) {
        $stripped = $line.Trim()
        if ($stripped -match '^sbSql\.append\s*\(\s*(.*?)\s*\)\s*;?\s*$') {
            $inner = $Matches[1]
            $sb = [System.Text.StringBuilder]::new()
            $pos = 0
            while ($pos -lt $inner.Length) {
                if ($inner[$pos] -eq '"') {
                    $end = $pos + 1
                    while ($end -lt $inner.Length -and $inner[$end] -ne '"') {
                        if ($inner[$end] -eq '\') { $end++ }
                        $end++
                    }
                    if ($end -gt $pos + 1) {
                        [void]$sb.Append($inner.Substring($pos + 1, $end - $pos - 1))
                    }
                    $pos = $end + 1
                } else {
                    $sub = $inner.Substring($pos)
                    if ($sub -match '^\s*\+\s*([A-Za-z_]\w*)\s*(\+)?\s*') {
                        [void]$sb.Append('{?' + $Matches[1] + '}')
                        $pos += $Matches[0].Length
                    } else {
                        $pos++
                    }
                }
            }
            $parts.Add($sb.ToString())
        } elseif ($stripped) {
            $parts.Add($line)
        }
    }
    return $parts -join "`n"
}

# ── 主要轉換邏輯 ──────────────────────────────────────────
$result = $text

switch ($Mode) {

    "convert" {
        $result = ConvertJavaConcat $result
        $result = ConvertJavaAppend $result
        # {?param} → :param
        $result = [regex]::Replace($result, '\{[?](\w+)\}', ':$1')
        # IN_XXX → :IN_XXX（全大寫 IN_ 開頭）
        $result = [regex]::Replace($result, '\bIN_[A-Z][A-Z0-9_]+\b', ':$0')
    }

    "reverse" {
        # :IN_XXX → IN_XXX（先處理，避免被下一步誤判）
        $result = [regex]::Replace($result, ':(IN_[A-Z][A-Z0-9_]+)', '$1')
        # :param → {?param}
        $result = [regex]::Replace($result, ':([A-Za-z_]\w*)', '{?$1}')
    }

    "to-append" {
        $lines = ($result -split "`n") | Where-Object { $_.Trim() -ne '' }
        $result = ($lines | ForEach-Object {
            "${JavaVar}.append(`" $($_.Trim()) `");"
        }) -join "`n"
    }

    "to-concat" {
        $lines = ($result -split "`n") | Where-Object { $_.Trim() -ne '' }
        if ($lines.Count -eq 0) { break }
        $out = [System.Collections.Generic.List[string]]::new()
        $out.Add("String ${JavaVar} = `" $($lines[0].Trim()) `"")
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $out.Add("    + `" $($lines[$i].Trim()) `"")
        }
        $result = ($out -join "`n") + ";"
    }
}

# ── 寫回剪貼簿 ────────────────────────────────────────────
$result = $result.Trim()
Set-Clipboard -Value $result
Write-Host "✓ 完成 ($Mode) — 已複製到剪貼簿，請按 Ctrl+V 貼回" -ForegroundColor Green
