#Requires -RunAsAdministrator
<#
.SYNOPSIS
    WOLターゲットPC(レッツノート)のWindows側設定を自動で行うスクリプト。

.DESCRIPTION
    以下を自動で設定します:
      1. MACアドレスの確認(デスクトップに wol_mac_address.txt として保存)
      2. 有線LANアダプターのWake on Magic Packet有効化(ステップ3)
      3. 高速スタートアップの無効化(ステップ3・シャットダウンからのWOLに必須)
      4. netplwizで自動ログイン設定用のチェックボックスを表示させる準備(ステップ4)

    実行方法(管理者PowerShellで):
      powershell -ExecutionPolicy Bypass -File .\setup_target_pc.ps1

    BIOS設定(ステップ2)と自動ログインの最終設定(ステップ4)は手動です。
    実行後に表示される「残りの手動作業」を確認してください。
#>

$ErrorActionPreference = "Continue"
Write-Host "==== WOL ターゲットPC セットアップ(レッツノート用) ====" -ForegroundColor Cyan

# --- 1. 有線LANアダプターの検出とMACアドレスの保存 -------------------------
Write-Host "`n[1/4] 有線LANアダプターを検出中..." -ForegroundColor Yellow

$wiredAdapters = Get-NetAdapter -Physical | Where-Object {
    $_.PhysicalMediaType -eq "802.3" -or $_.InterfaceDescription -match "Ethernet|GbE|I219|I225|Realtek PCIe"
}

if (-not $wiredAdapters) {
    Write-Host "有線LANアダプターが見つかりませんでした。" -ForegroundColor Red
    Write-Host "USB-LANアダプターを使っている場合は接続してから再実行してください。" -ForegroundColor Red
    Write-Host "(注意: USB-LANアダプターは電源オフ中に通電されないため、WOLには内蔵有線LANポートを推奨)" -ForegroundColor Red
    exit 1
}

$macFile = Join-Path ([Environment]::GetFolderPath("Desktop")) "wol_mac_address.txt"
$macLines = foreach ($a in $wiredAdapters) {
    "アダプター: $($a.Name) / $($a.InterfaceDescription)`nMACアドレス: $($a.MacAddress)`n状態: $($a.Status)`n"
}
$macLines | Out-File -FilePath $macFile -Encoding UTF8

foreach ($a in $wiredAdapters) {
    Write-Host ("  検出: {0} ({1})" -f $a.Name, $a.InterfaceDescription)
    Write-Host ("  ★ MACアドレス: {0}" -f $a.MacAddress) -ForegroundColor Green
}
Write-Host "  → デスクトップの wol_mac_address.txt にも保存しました。"

# --- 2. Wake on Magic Packet の有効化 --------------------------------------
Write-Host "`n[2/4] Wake on Magic Packet を有効化中..." -ForegroundColor Yellow

foreach ($a in $wiredAdapters) {
    # 電源管理: マジックパケットでのスリープ解除を許可
    try {
        Set-NetAdapterPowerManagement -Name $a.Name -WakeOnMagicPacket Enabled -ErrorAction Stop
        Write-Host "  [$($a.Name)] 電源管理: Wake on Magic Packet = 有効" -ForegroundColor Green
    } catch {
        Write-Host "  [$($a.Name)] 電源管理の設定に失敗: $_" -ForegroundColor Red
    }

    # ドライバー詳細設定: *WakeOnMagicPacket (標準レジストリキーワード)
    $prop = Get-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword "*WakeOnMagicPacket" -ErrorAction SilentlyContinue
    if ($prop) {
        Set-NetAdapterAdvancedProperty -Name $a.Name -RegistryKeyword "*WakeOnMagicPacket" -RegistryValue 1
        Write-Host "  [$($a.Name)] 詳細設定: *WakeOnMagicPacket = 1" -ForegroundColor Green
    } else {
        Write-Host "  [$($a.Name)] 詳細設定に *WakeOnMagicPacket が無いためスキップ(ドライバーによっては正常)"
    }

    # このデバイスによるスタンバイ解除を許可
    powercfg /deviceenablewake "$($a.InterfaceDescription)" 2>$null
    Write-Host "  [$($a.Name)] スタンバイ解除の許可: 設定済み" -ForegroundColor Green
}

# --- 3. 高速スタートアップの無効化 -----------------------------------------
Write-Host "`n[3/4] 高速スタートアップを無効化中..." -ForegroundColor Yellow

$powerKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power"
Set-ItemProperty -Path $powerKey -Name "HiberbootEnabled" -Value 0 -Type DWord
Write-Host "  高速スタートアップ: 無効化しました(シャットダウンからのWOLに必須)" -ForegroundColor Green

# --- 4. 自動ログイン設定の準備 ----------------------------------------------
Write-Host "`n[4/4] 自動ログイン設定の準備中..." -ForegroundColor Yellow

# netplwiz に「ユーザー名とパスワードの入力が必要」チェックボックスを表示させる
$passwordLessKey = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device"
if (-not (Test-Path $passwordLessKey)) {
    New-Item -Path $passwordLessKey -Force | Out-Null
}
Set-ItemProperty -Path $passwordLessKey -Name "DevicePasswordLessBuildVersion" -Value 0 -Type DWord
Write-Host "  netplwiz のチェックボックスを表示可能にしました" -ForegroundColor Green
Write-Host "  (パスワードを扱うため、自動ログインの最終設定は手動で行います)"

# --- 完了サマリー -------------------------------------------------------------
Write-Host @"

==== 自動設定が完了しました ====

■ 残りの手動作業(3つ):

  (1) BIOS設定 ※最重要
      PCを再起動し、Panasonicロゴが出たら F2 キーを連打
      →「詳細」メニュー →「Power on by LAN機能」を「許可」に変更
      → F10 で保存して終了

  (2) 自動ログイン
      Win + R →「netplwiz」と入力して Enter
      → 対象ユーザーを選択
      →「ユーザーがこのコンピューターを使うには、ユーザー名とパスワードの
         入力が必要」のチェックを外す → 適用 → パスワードを入力

  (3) 常駐ツールの登録(遠隔操作に使う場合)
      Win + R →「shell:startup」→ 開いたフォルダーに
      Claude Desktop等のショートカットを入れる

■ レッツノートでの注意:
  ・シャットダウンからのWOLは ACアダプターを挿したまま にしてください
  ・LANケーブル(有線)を接続したままにしてください
  ・MACアドレスはデスクトップの wol_mac_address.txt を参照

"@ -ForegroundColor Cyan
