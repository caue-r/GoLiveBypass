<#
    GoLiveBypass - instalador com janela

    Uma janela com dois botoes: instalar e desinstalar. Nada de terminal, nada de escolhas.

    O trabalho pesado nao esta aqui: quem instala e o GoLiveBypass-Installer.ps1, que roda
    como processo filho e tem a saida jogada no log da janela. Assim existe uma logica so,
    e a janela e apenas uma cara bonita para ela.

    Uso:
      .\GoLiveBypass-Setup.ps1
#>

[CmdletBinding()]
param(
    # Uso interno: marca a copia que ja subiu com permissao de administrador, para ela nao
    # tentar se elevar de novo em laco caso a elevacao nao pegue.
    [switch] $Elevated
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRaw = 'https://raw.githubusercontent.com/caue-r/GoLiveBypass/main'
$EngineName = 'GoLiveBypass-Installer.ps1'
$PowerShellExe = Join-Path $PSHOME 'powershell.exe'

# --------------------------------------------------------------------------- administrador

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal] $identity).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

# O winget precisa de administrador para instalar o Node e o Git para a maquina toda. Pedir
# a elevacao agora, uma vez, e melhor do que a instalacao falhar no meio.
if (-not $Elevated -and -not (Test-Admin) -and $PSCommandPath) {
    try {
        # Sem -WindowStyle Hidden aqui: a copia elevada esconde o proprio console sozinha,
        # e passar Hidden esconderia junto a janela do instalador.
        Start-Process -FilePath $PowerShellExe -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass',
            '-File', "`"$PSCommandPath`"", '-Elevated'
        )
        exit 0
    } catch {
        # Recusou o UAC: segue sem administrador. Da para instalar o plugin num Equicord que
        # ja existe; so a instalacao do Node/Git pelo winget e que pode falhar.
    }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# O terminal preto que abre junto e escondido aqui, pelo proprio script, e nao com um
# "-WindowStyle Hidden" na chamada: esse parametro vira o nCmdShow inicial do processo e a
# primeira janela criada o herda, ou seja, ele escondia a janela do instalador tambem.
Add-Type -Namespace Glb -Name Console -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int how);
'@
$consoleWindow = [Glb.Console]::GetConsoleWindow()
if ($consoleWindow -ne [IntPtr]::Zero) { [Glb.Console]::ShowWindow($consoleWindow, 0) | Out-Null }

# ---------------------------------------------------------------------------------- motor

function Get-EnginePath {
    if ($PSScriptRoot) {
        $local = Join-Path $PSScriptRoot $EngineName
        if (Test-Path -LiteralPath $local) { return $local }
    }

    $cached = Join-Path $env:TEMP $EngineName
    Invoke-WebRequest -UseBasicParsing -Uri "$RepoRaw/installer/$EngineName" -OutFile $cached
    return $cached
}

try {
    $EnginePath = Get-EnginePath
} catch {
    [System.Windows.Forms.MessageBox]::Show(
        "Nao consegui obter o instalador.`n`n$($_.Exception.Message)",
        'GoLiveBypass', 'OK', 'Error') | Out-Null
    exit 1
}

# Carrega so as funcoes de deteccao (nao instala nada) para a janela mostrar o que achou.
. $EnginePath -AsLibrary

# ---------------------------------------------------------------------------------- janela

$Ink = @{
    Back   = [System.Drawing.Color]::FromArgb(24, 25, 28)
    Panel  = [System.Drawing.Color]::FromArgb(33, 35, 39)
    Text   = [System.Drawing.Color]::FromArgb(232, 234, 237)
    Muted  = [System.Drawing.Color]::FromArgb(150, 154, 161)
    Accent = [System.Drawing.Color]::FromArgb(88, 166, 255)
    Green  = [System.Drawing.Color]::FromArgb(46, 160, 67)
    Red    = [System.Drawing.Color]::FromArgb(180, 60, 60)
}

function New-Label($text, $x, $y, $w, $h, $size, $color, $style) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $text
    $label.Location = New-Object System.Drawing.Point($x, $y)
    $label.Size = New-Object System.Drawing.Size($w, $h)
    $label.Font = New-Object System.Drawing.Font('Segoe UI', $size, $style)
    $label.ForeColor = $color
    $label.BackColor = [System.Drawing.Color]::Transparent
    return $label
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'GoLiveBypass'
$form.ClientSize = New-Object System.Drawing.Size(660, 596)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.BackColor = $Ink.Back

$form.Controls.Add((New-Label 'GoLiveBypass' 24 20 400 34 17 $Ink.Accent ([System.Drawing.FontStyle]::Bold)))
$form.Controls.Add((New-Label 'Go Live e camera de volta no Discord' 26 54 500 20 9.5 $Ink.Muted ([System.Drawing.FontStyle]::Regular)))

$statusPanel = New-Object System.Windows.Forms.Panel
$statusPanel.Location = New-Object System.Drawing.Point(24, 88)
$statusPanel.Size = New-Object System.Drawing.Size(612, 84)
$statusPanel.BackColor = $Ink.Panel
$form.Controls.Add($statusPanel)

$statusLabel = New-Label 'Procurando...' 16 12 580 60 9.5 $Ink.Text ([System.Drawing.FontStyle]::Regular)
$statusLabel.Font = New-Object System.Drawing.Font('Consolas', 9.5)
$statusPanel.Controls.Add($statusLabel)

function New-Button($text, $x, $w, $color) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text
    $button.Location = New-Object System.Drawing.Point($x, 190)
    $button.Size = New-Object System.Drawing.Size($w, 56)
    $button.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
    $button.ForeColor = [System.Drawing.Color]::White
    $button.BackColor = $color
    $button.FlatStyle = 'Flat'
    $button.FlatAppearance.BorderSize = 0
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $button
}

$installButton = New-Button 'Instalar / Reinstalar' 24 388 $Ink.Green
$uninstallButton = New-Button 'Desinstalar' 428 208 $Ink.Red
$form.Controls.Add($installButton)
$form.Controls.Add($uninstallButton)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(24, 258)
$progress.Size = New-Object System.Drawing.Size(612, 6)
$progress.Style = 'Marquee'
$progress.MarqueeAnimationSpeed = 0
# Parada, a barra fica uma faixa branca que parece defeito. So aparece enquanto trabalha.
$progress.Visible = $false
$form.Controls.Add($progress)

$form.Controls.Add((New-Label 'O que esta acontecendo' 24 278 300 20 9 $Ink.Muted ([System.Drawing.FontStyle]::Regular)))

$log = New-Object System.Windows.Forms.TextBox
$log.Location = New-Object System.Drawing.Point(24, 302)
$log.Size = New-Object System.Drawing.Size(612, 244)
$log.Multiline = $true
$log.ReadOnly = $true
$log.ScrollBars = 'Vertical'
$log.BackColor = $Ink.Panel
$log.ForeColor = $Ink.Text
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.BorderStyle = 'None'
$form.Controls.Add($log)

$footer = New-Label 'Pronto para comecar.' 24 558 612 20 9 $Ink.Muted ([System.Drawing.FontStyle]::Regular)
$form.Controls.Add($footer)

# ------------------------------------------------------------------------------ execucao

# A saida do processo filho chega numa thread que nao e a da janela, e mexer em controle do
# WinForms fora da thread dele quebra. Por isso as linhas entram numa fila sincronizada e
# quem escreve no log e um timer, que ja roda na thread certa.
$global:GlbQueue = [System.Collections.Queue]::Synchronized((New-Object System.Collections.Queue))
$global:GlbProc = $null
$global:GlbSubs = @()
$global:GlbAction = ''

function Write-Log($text) {
    $log.AppendText($text + [Environment]::NewLine)
    $log.SelectionStart = $log.TextLength
    $log.ScrollToCaret()
}

function Update-Status {
    $lines = @()

    $discord = @(Get-DiscordResources).Count
    if ($discord -gt 0) { $lines += "Discord   instalado ($discord versao(oes))" }
    else { $lines += 'Discord   nao encontrado' }

    $mod = Get-InstalledMod
    if ($mod) { $lines += "Mod       $mod" } else { $lines += 'Mod       nenhum' }

    # So a busca pela injecao, que le dois arquivos: a varredura de disco do motor pode
    # demorar segundos e congelaria a janela.
    $root = Find-CheckoutFromInjection
    if ($root) {
        $lines += "Fonte     $root"
        if (Test-Path -LiteralPath (Join-Path $root "src\userplugins\$PluginDirName")) {
            $lines += 'Plugin    ja instalado'
        } else {
            $lines += 'Plugin    nao instalado'
        }
    } else {
        $lines += 'Fonte     sera procurado (ou baixado) ao instalar'
    }

    $statusLabel.Text = $lines -join [Environment]::NewLine
}

function Set-Busy($busy) {
    $installButton.Enabled = -not $busy
    $uninstallButton.Enabled = -not $busy
    $progress.Visible = $busy
    if ($busy) { $progress.MarqueeAnimationSpeed = 30 } else { $progress.MarqueeAnimationSpeed = 0 }
}

function Start-Engine($mode, $friendly) {
    if ($global:GlbProc -and -not $global:GlbProc.HasExited) { return }

    $global:GlbAction = $friendly
    $log.Clear()
    Set-Busy $true
    $footer.Text = "$friendly em andamento. Pode demorar alguns minutos na primeira vez."
    Write-Log "== $friendly =="

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $PowerShellExe
    $psi.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1} -Yes' -f $EnginePath, $mode
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    # Aqui nao existe teclado ligado no processo. Sem isto, qualquer programa que resolva
    # perguntar alguma coisa fica esperando uma resposta que nunca vem, e a janela fica
    # "instalando" para sempre. Com o stdin fechado ele leva um EOF e falha rapido, que pelo
    # menos aparece no log.
    $psi.RedirectStandardInput = $true

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $onData = { if ($null -ne $EventArgs.Data) { $global:GlbQueue.Enqueue($EventArgs.Data) } }
    $global:GlbSubs = @(
        (Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $onData)
        (Register-ObjectEvent -InputObject $proc -EventName ErrorDataReceived -Action $onData)
    )

    $proc.Start() | Out-Null
    $proc.StandardInput.Close()
    $proc.BeginOutputReadLine()
    $proc.BeginErrorReadLine()
    $global:GlbProc = $proc
}

function Complete-Engine {
    $code = $global:GlbProc.ExitCode
    $action = $global:GlbAction

    foreach ($sub in $global:GlbSubs) { Unregister-Event -SubscriptionId $sub.Id -ErrorAction SilentlyContinue }
    $global:GlbSubs = @()
    $global:GlbProc = $null

    Set-Busy $false
    Update-Status

    if ($code -eq 0) {
        $footer.Text = "$action concluido."
        [System.Windows.Forms.MessageBox]::Show(
            "$action concluido.`n`nO Discord ja foi reiniciado com o plugin ativado. Entre numa call e use Go Live ou a camera.",
            'GoLiveBypass', 'OK', 'Information') | Out-Null
        return
    }

    # 3 = o motor instalou o Node/Git mas o Windows ainda nao registrou. E o unico caso em
    # que reiniciar o computador resolve de verdade.
    if ($code -eq 3) {
        $footer.Text = 'Precisa reiniciar o computador para terminar.'
        $answer = [System.Windows.Forms.MessageBox]::Show(
            "Instalei o que faltava (Node/Git), mas o Windows so vai reconhecer depois de reiniciar.`n`nReiniciar o computador agora? Depois e so abrir este instalador de novo e clicar em Instalar.",
            'GoLiveBypass', 'YesNo', 'Warning')
        if ($answer -eq 'Yes') { & shutdown.exe /r /t 5 /c 'GoLiveBypass: reiniciando para terminar a instalacao' }
        return
    }

    $footer.Text = "$action falhou. Veja o log acima."
    [System.Windows.Forms.MessageBox]::Show(
        "$action nao terminou.`n`nA ultima linha do log diz o motivo.",
        'GoLiveBypass', 'OK', 'Error') | Out-Null
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 120
$timer.Add_Tick({
    while ($global:GlbQueue.Count -gt 0) { Write-Log ([string] $global:GlbQueue.Dequeue()) }

    if ($global:GlbProc -and $global:GlbProc.HasExited) {
        # Um tick a mais para a fila esvaziar antes de julgar o resultado.
        if ($global:GlbQueue.Count -eq 0) { Complete-Engine }
    }
})

$installButton.Add_Click({ Start-Engine 'Install' 'Instalacao' })
$uninstallButton.Add_Click({ Start-Engine 'Uninstall' 'Desinstalacao' })

$form.Add_Shown({
    # Sem isso a janela pode nascer atras do que ja estava aberto, e a pessoa acha que o
    # atalho nao fez nada.
    $form.Activate()
    $form.BringToFront()

    Update-Status
    $timer.Start()
    if (-not (Test-Admin)) {
        Write-Log '[!] Rodando sem administrador. Se faltar Node ou Git, a instalacao deles pode falhar.'
    }
})

$form.Add_FormClosing({
    if ($global:GlbProc -and -not $global:GlbProc.HasExited) {
        $answer = [System.Windows.Forms.MessageBox]::Show(
            'A instalacao ainda esta rodando. Fechar agora pode deixar o Discord pela metade. Fechar mesmo assim?',
            'GoLiveBypass', 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { $_.Cancel = $true; return }
    }
    $timer.Stop()
})

[System.Windows.Forms.Application]::Run($form)
