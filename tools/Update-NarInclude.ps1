# Update-NarInclude.ps1
#
# 配布用 nar に入れるファイルの一覧（.narinclude）を作り直す。
# また、作った nar の中身がその一覧と一致しているかを確かめる。
#
#   .narinclude を作り直す
#     powershell -ExecutionPolicy Bypass -File tools\Update-NarInclude.ps1
#
#   nar の中身を突き合わせる
#     powershell -ExecutionPolicy Bypass -File tools\Update-NarInclude.ps1 -Verify <nar のパス>
#
# 配る物の決め方
#   1. git に登録されているファイル（git ls-files）だけが候補になる。
#      開発フォルダに置いただけのファイル（動作確認用のサプリメント、セーブデータなど）は入らない。
#   2. md5buildignore.txt に当たるものを除く。判定は git に任せる。
#      ネットワーク更新と nar で「配らない物」の定義を 1 か所にまとめるため。
#   3. nar とネットワーク更新で扱いが違うものだけ、下の 2 つのリストで調整する。
#
# .narinclude はファイル単位で書く（フォルダ単位の行を作らない）。
# フォルダ単位にすると、そのフォルダに後から置かれた見知らぬファイルも nar に入るため。
#
# 終了コード
#   0  正常（-Verify では「一致」）
#   1  -Verify で余分・不足があった
#   2  git が使えない、ファイルが無いなど

param(
    [string] $Verify
)

# 更新からは外すが、nar には入れるもの（リポジトリのルートからのパス。末尾 / はフォルダ）
$NarOnlyInclude = @(
    'LilyNovelPlayerBallon/'
)

# 更新には入れるが、nar には入れないもの
$NarOnlyExclude = @(
)

# nar に入っていたら特に目立たせるもの（正規表現）
$Dangerous = @(
    '(^|/)satori_save(data|backup)\.(txt|sat)$',
    '(^|/)profile/',
    '^\.git/',
    '^\.workspace/',
    '^ghost/master/scenarios/(?!master/)',
    '^shell/(?!master/)'
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = $utf8 } catch {}

$root = Split-Path $PSScriptRoot -Parent
$narinclude = Join-Path $root '.narinclude'
$ignoreFile = Join-Path $root 'md5buildignore.txt'

function Invoke-GitList([string[]] $GitArgs) {
    $out = & git -C $root -c core.quotepath=off @GitArgs
    if ($LASTEXITCODE -ne 0) { throw "git の実行に失敗しました: git $($GitArgs -join ' ')" }
    return @($out | Where-Object { $_ -ne '' })
}

# 配るべきファイルの一覧（ルートからの相対パス、/ 区切り）
function Get-Expected {
    if (-not (Test-Path $ignoreFile)) { throw "md5buildignore.txt がありません: $ignoreFile" }

    $all = Invoke-GitList @('ls-files', '--cached')
    $ignored = Invoke-GitList @('ls-files', '--cached', '--ignored', "--exclude-from=$ignoreFile")
    $ignoredSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($p in $ignored) { [void]$ignoredSet.Add($p) }
    # 作業ツリーで消したファイルは、git rm する前でも nar には入らないので候補から外す
    foreach ($p in (Invoke-GitList @('ls-files', '--deleted'))) { [void]$ignoredSet.Add($p) }

    $result = New-Object 'System.Collections.Generic.List[string]'
    foreach ($p in $all) {
        $forced = $false
        foreach ($inc in $NarOnlyInclude) {
            if ($p -eq $inc -or ($inc.EndsWith('/') -and $p.StartsWith($inc, [StringComparison]::Ordinal))) { $forced = $true }
        }
        $dropped = $false
        foreach ($exc in $NarOnlyExclude) {
            if ($p -eq $exc -or ($exc.EndsWith('/') -and $p.StartsWith($exc, [StringComparison]::Ordinal))) { $dropped = $true }
        }
        if ($dropped) { continue }
        if ($ignoredSet.Contains($p) -and -not ($forced -and (Test-Path -LiteralPath (Join-Path $root $p)))) { continue }
        $result.Add($p)
    }
    $arr = $result.ToArray()
    [Array]::Sort($arr, [StringComparer]::Ordinal)
    return ,$arr
}

# gitignore 書式で特別な意味を持つ文字をエスケープする
function ConvertTo-IgnorePattern([string] $path) {
    $s = $path -replace '([\\\*\?\[\]])', '\$1'
    if ($s.EndsWith(' ')) { $s = $s.Substring(0, $s.Length - 1) + '\ ' }
    return '/' + $s
}

function ConvertFrom-IgnorePattern([string] $line) {
    $s = $line
    if ($s.StartsWith('/')) { $s = $s.Substring(1) }
    return ($s -replace '\\(.)', '$1')
}

function Read-NarInclude {
    if (-not (Test-Path $narinclude)) { return @() }
    $lines = [System.IO.File]::ReadAllLines($narinclude, $utf8)
    return @($lines | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') } | ForEach-Object { ConvertFrom-IgnorePattern $_ })
}

function Compare-List([string[]] $old, [string[]] $new) {
    $o = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $n = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $old = @($old | Where-Object { $_ })
    $new = @($new | Where-Object { $_ })
    foreach ($x in $old) { [void]$o.Add($x) }
    foreach ($x in $new) { [void]$n.Add($x) }
    $added = @($new | Where-Object { -not $o.Contains($_) })
    $removed = @($old | Where-Object { -not $n.Contains($_) })
    return @{ Added = $added; Removed = $removed }
}

try {
    $null = & git --version
} catch {
    Write-Output 'git が見つかりません。'
    exit 2
}

try {
    $expected = Get-Expected
} catch {
    Write-Output $_.Exception.Message
    exit 2
}

# ---------------------------------------------------------------------------
# 突き合わせ
# ---------------------------------------------------------------------------
if ($Verify) {
    if (-not (Test-Path $Verify)) { Write-Output "nar がありません: $Verify"; exit 2 }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $Verify).Path)
    try {
        $inNar = @($zip.Entries | ForEach-Object { $_.FullName.Replace('\', '/') } | Where-Object { -not $_.EndsWith('/') })
    } finally {
        $zip.Dispose()
    }

    $diff = Compare-List $expected $inNar
    $extra = $diff.Added       # nar にあるが、配るべき一覧に無い
    $missing = $diff.Removed   # 配るべき一覧にあるが、nar に無い

    $stale = Compare-List (Read-NarInclude) $expected
    if ($stale.Added.Count -gt 0 -or $stale.Removed.Count -gt 0) {
        Write-Output '注意: .narinclude が古いままです。引数なしで実行して作り直してから、nar を作り直してください。'
        Write-Output ''
    }

    if ($extra.Count -eq 0 -and $missing.Count -eq 0) {
        Write-Output "一致（$($expected.Count) ファイル）"
        exit 0
    }

    if ($extra.Count -gt 0) {
        Write-Output "余分（nar に入っているが、配る物ではない）: $($extra.Count) 件"
        foreach ($p in $extra) {
            $mark = '   '
            foreach ($re in $Dangerous) { if ($p -match $re) { $mark = '!! ' } }
            Write-Output "  $mark$p"
        }
        Write-Output ''
    }
    if ($missing.Count -gt 0) {
        Write-Output "不足（配る物なのに、nar に入っていない）: $($missing.Count) 件"
        foreach ($p in $missing) { Write-Output "     $p" }
        Write-Output ''
    }
    Write-Output '!! はセーブデータ・profile・.git・他人のシナリオやシェルなど、特に入ってはいけないもの。'
    exit 1
}

# ---------------------------------------------------------------------------
# .narinclude を作り直す
# ---------------------------------------------------------------------------
foreach ($p in $expected) {
    if ($p -match '[^\x20-\x7E]') { Write-Output "警告: ASCII 以外の文字を含むパスがあります（SSP が正しく読むか未確認）: $p" }
}

$existed = Test-Path $narinclude
$before = Read-NarInclude

$sb = New-Object System.Text.StringBuilder
[void]$sb.Append("# このファイルは tools/Update-NarInclude.ps1 が作る。手で編集しない。`r`n")
[void]$sb.Append("# ここに書いたものだけが nar に入る（SSP の .narinclude。書式は gitignore と同じ）。`r`n")
foreach ($p in $expected) { [void]$sb.Append((ConvertTo-IgnorePattern $p) + "`r`n") }
[System.IO.File]::WriteAllText($narinclude, $sb.ToString(), $utf8)

$diff = Compare-List $before $expected
Write-Output ".narinclude を作り直しました（$($expected.Count) ファイル）"
if (-not $existed) {
    Write-Output '（新しく作りました。中身は .narinclude を見てください）'
} elseif ($diff.Added.Count -eq 0 -and $diff.Removed.Count -eq 0) {
    Write-Output '前回からの変更はありません。'
} else {
    foreach ($p in $diff.Added) { Write-Output "  + $p" }
    foreach ($p in $diff.Removed) { Write-Output "  - $p" }
}
exit 0
