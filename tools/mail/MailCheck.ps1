# MailCheck.ps1
# Полный аудит почтового домена (SPF, DKIM, DMARC, MX, rDNS, TLS, Reputation)
# Автор: DeVolaris | GPT-5

function Show-Menu {
    Clear-Host
    Write-Host "=============================" -ForegroundColor Cyan
    Write-Host "   📧 MailCheck — Аудит почтового домена"
    Write-Host "=============================" -ForegroundColor Cyan
    Write-Host "1. Проверить Reverse DNS (PTR)"
    Write-Host "2. Проверить MX-записи"
    Write-Host "3. Проверить SPF"
    Write-Host "4. Проверить DKIM"
    Write-Host "5. Проверить DMARC"
    Write-Host "6. Проверить TLS (STARTTLS)"
    Write-Host "7. Проверить репутацию (Spamhaus, MXToolbox)"
    Write-Host "8. Проверить всё подряд"
    Write-Host "0. Выход"
    Write-Host ""
}

function Check-RDNS {
    param([string]$IP)
    Write-Host "`n🔍 Проверка Reverse DNS для IP:" $IP -ForegroundColor Cyan
    try {
        $ptr = (Resolve-DnsName -Name $IP -Type PTR -ErrorAction Stop).NameHost
        Write-Host "✅ PTR найден: $ptr" -ForegroundColor Green
    } catch {
        Write-Host "❌ PTR не найден (настройте reverse DNS на хостинг-панели)." -ForegroundColor Red
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
    $selector = Read-Host "Введите DKIM selector (например: default)"
    $record = "$selector._domainkey.$Domain"
    try {
        $dkim = (Resolve-DnsName -Name $record -Type TXT -ErrorAction Stop).Strings
        if ($dkim) { Write-Host "✅ DKIM найден: $dkim" -ForegroundColor Green } else { Write-Host "⚠️ DKIM пуст." -ForegroundColor Yellow }
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

function Check-TLS {
    param([string]$MailServer)
    Write-Host "`n🔒 Проверка STARTTLS для:" $MailServer -ForegroundColor Cyan
    try {
        $tcp = Test-NetConnection -ComputerName $MailServer -Port 25 -InformationLevel Detailed
        if ($tcp.TcpTestSucceeded) {
            Write-Host "✅ Порт 25 доступен. Проверяем STARTTLS..." -ForegroundColor Green
            try {
                $tls = openssl s_client -starttls smtp -connect "$MailServer:25" 2>$null
                if ($tls -match "Verify return code: 0") {
                    Write-Host "✅ Сертификат действителен и поддерживается STARTTLS." -ForegroundColor Green
                } else {
                    Write-Host "⚠️ STARTTLS доступен, но сертификат может быть недействительным." -ForegroundColor Yellow
                }
            } catch {
                Write-Host "⚠️ Не удалось выполнить TLS handshake." -ForegroundColor Yellow
            }
        } else {
            Write-Host "❌ Порт 25 недоступен." -ForegroundColor Red
        }
    } catch {
        Write-Host "❌ Ошибка проверки TLS." -ForegroundColor Red
    }
}

function Check-Reputation {
    param([string]$Domain, [string]$IP)
    Write-Host "`n🌐 Проверка репутации:" -ForegroundColor Cyan
    Write-Host "→ Spamhaus: https://check.spamhaus.org/listed/?search=$IP" -ForegroundColor Gray
    Write-Host "→ MXToolbox: https://mxtoolbox.com/SuperTool.aspx?action=blacklist%3a$IP" -ForegroundColor Gray
    Write-Host "→ MXToolbox Mail Test: https://mxtoolbox.com/SuperTool.aspx?action=mx%3a$Domain" -ForegroundColor Gray
    Write-Host "`n(Откройте ссылки для просмотра детальной информации)" -ForegroundColor Yellow
}

# Меню
do {
    Show-Menu
    $choice = Read-Host "Выберите пункт меню"
    switch ($choice) {
        "1" { $ip = Read-Host "Введите IP"; Check-RDNS -IP $ip; Pause }
        "2" { $domain = Read-Host "Введите домен"; Check-MX -Domain $domain; Pause }
        "3" { $domain = Read-Host "Введите домен"; Check-SPF -Domain $domain; Pause }
        "4" { $domain = Read-Host "Введите домен"; Check-DKIM -Domain $domain; Pause }
        "5" { $domain = Read-Host "Введите домен"; Check-DMARC -Domain $domain; Pause }
        "6" { $mail = Read-Host "Введите адрес почтового сервера (например: mail.domain.com)"; Check-TLS -MailServer $mail; Pause }
        "7" { $domain = Read-Host "Введите домен"; $ip = Read-Host "Введите IP"; Check-Reputation -Domain $domain -IP $ip; Pause }
        "8" { 
            $domain = Read-Host "Введите домен"
            $ip = Read-Host "Введите IP"
            Check-RDNS -IP $ip
            Check-MX -Domain $domain
            Check-SPF -Domain $domain
            Check-DKIM -Domain $domain
            Check-DMARC -Domain $domain
            Check-TLS -MailServer "mail.$domain"
            Check-Reputation -Domain $domain -IP $ip
            Pause
        }
        "0" { break }
        default { Write-Host "❗ Неверный выбор, попробуйте снова." -ForegroundColor Yellow }
    }
} while ($choice -ne "0")

Write-Host "`nЗавершено." -ForegroundColor Cyan
