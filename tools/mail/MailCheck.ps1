# MailCheck.ps1
# Универсальный скрипт проверки конфигурации почтового домена
# Автор: DeVolaris | GPT-5

function Show-Menu {
    Clear-Host
    Write-Host "=============================" -ForegroundColor Cyan
    Write-Host "   📧 Проверка почтового домена"
    Write-Host "=============================" -ForegroundColor Cyan
    Write-Host "1. Проверить Reverse DNS (PTR)"
    Write-Host "2. Проверить MX-записи"
    Write-Host "3. Проверить SPF"
    Write-Host "4. Проверить DKIM"
    Write-Host "5. Проверить DMARC"
    Write-Host "6. Проверить всё подряд"
    Write-Host "0. Выход"
    Write-Host ""
}

function Check-RDNS {
    param([string]$IP)
    Write-Host "`n🔍 Проверка Reverse DNS для IP:" $IP -ForegroundColor Cyan
    try {
        $ptr = (Resolve-DnsName -Name $IP -Type PTR -ErrorAction Stop).NameHost
        Write-Host "✅ PTR-запись найдена: $ptr" -ForegroundColor Green
    } catch {
        Write-Host "❌ PTR не найден. Настройте обратную зону DNS (Reverse DNS)." -ForegroundColor Red
    }
}

function Check-MX {
    param([string]$Domain)
    Write-Host "`n📨 Проверка MX для домена:" $Domain -ForegroundColor Cyan
    try {
        $mx = Resolve-DnsName -Name $Domain -Type MX -ErrorAction Stop
        foreach ($r in $mx) { Write-Host "✅ MX: " $r.NameExchange " (приоритет: $($r.Preference))" -ForegroundColor Green }
    } catch {
        Write-Host "❌ MX-записи не найдены." -ForegroundColor Red
    }
}

function Check-SPF {
    param([string]$Domain)
    Write-Host "`n☀️ Проверка SPF:" -ForegroundColor Cyan
    try {
        $spf = (Resolve-DnsName -Name $Domain -Type TXT -ErrorAction Stop).Strings | Where-Object {$_ -match "v=spf1"}
        if ($spf) { Write-Host "✅ SPF найден: $spf" -ForegroundColor Green } else { Write-Host "⚠️ SPF отсутствует." -ForegroundColor Yellow }
    } catch {
        Write-Host "❌ Ошибка при проверке SPF." -ForegroundColor Red
    }
}

function Check-DKIM {
    param([string]$Domain)
    Write-Host "`n🔐 Проверка DKIM:" -ForegroundColor Cyan
    $selector = Read-Host "Введите DKIM selector (например: default или mail)"
    $record = "$selector._domainkey.$Domain"
    try {
        $dkim = (Resolve-DnsName -Name $record -Type TXT -ErrorAction Stop).Strings
        if ($dkim) { Write-Host "✅ DKIM найден: $dkim" -ForegroundColor Green } else { Write-Host "⚠️ DKIM-запись пуста." -ForegroundColor Yellow }
    } catch {
        Write-Host "❌ DKIM-запись не найдена." -ForegroundColor Red
    }
}

function Check-DMARC {
    param([string]$Domain)
    Write-Host "`n📊 Проверка DMARC:" -ForegroundColor Cyan
    try {
        $dmarc = (Resolve-DnsName -Name "_dmarc.$Domain" -Type TXT -ErrorAction Stop).Strings
        if ($dmarc) { Write-Host "✅ DMARC найден: $dmarc" -ForegroundColor Green } else { Write-Host "⚠️ DMARC отсутствует." -ForegroundColor Yellow }
    } catch {
        Write-Host "❌ DMARC-запись не найдена." -ForegroundColor Red
    }
}

# ==== Основной цикл меню ====
do {
    Show-Menu
    $choice = Read-Host "Выберите пункт меню"
    switch ($choice) {
        "1" {
            $ip = Read-Host "Введите IP-адрес сервера"
            Check-RDNS -IP $ip
            Pause
        }
        "2" {
            $domain = Read-Host "Введите домен (пример: example.com)"
            Check-MX -Domain $domain
            Pause
        }
        "3" {
            $domain = Read-Host "Введите домен"
            Check-SPF -Domain $domain
            Pause
        }
        "4" {
            $domain = Read-Host "Введите домен"
            Check-DKIM -Domain $domain
            Pause
        }
        "5" {
            $domain = Read-Host "Введите домен"
            Check-DMARC -Domain $domain
            Pause
        }
        "6" {
            $domain = Read-Host "Введите домен"
            $ip = Read-Host "Введите IP-адрес"
            Check-RDNS -IP $ip
            Check-MX -Domain $domain
            Check-SPF -Domain $domain
            Check-DKIM -Domain $domain
            Check-DMARC -Domain $domain
            Pause
        }
        "0" { break }
        default { Write-Host "Неверный выбор. Попробуйте снова." -ForegroundColor Yellow }
    }
} while ($choice -ne "0")

Write-Host "`nЗавершено." -ForegroundColor Cyan
