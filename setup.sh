#!/bin/bash

# =============================================================================
# HAProxy-Nginx SCRIPT
# Автоматическая установка HAProxy + Nginx для SNI-маршрутизации VPN трафика
# =============================================================================

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# =============================================================================
# КОНФИГУРАЦИЯ ПО УМОЛЧАНИЮ
# =============================================================================

# Репозиторий static page
STATIC_PAGE_REPO="https://github.com/rasulovdd/static_page.git"

# Переменные (будут установлены пользователем)
DOMAIN=""
VPN_DOMAINS=()
HA_PROXY_CFG="/etc/haproxy/haproxy.cfg"
NGINX_SITE_CFG="/etc/nginx/sites-available/default"
SSL_CERT_PATH=""

# =============================================================================
# ФУНКЦИИ ВЫВОДА
# =============================================================================

print_header() {

    # Вывод шапки с информацией о проекте
    echo -e "\033[0;36m"
    echo "┌─────────────────────────────────────────────────────────────────────────────┐"
    echo "│ ██████╗  █████╗ ███████╗██╗   ██╗██╗      ██████╗ ██╗   ██╗██████╗ ██████╗  │"
    echo "│ ██╔══██╗██╔══██╗██╔════╝██║   ██║██║     ██╔═══██╗██║   ██║██╔══██╗██╔══██╗ │"
    echo "│ ██████╔╝███████║███████╗██║   ██║██║     ██║   ██║██║   ██║██║  ██║██║  ██║ │"
    echo "│ ██╔══██╗██╔══██║╚════██║██║   ██║██║     ██║   ██║╚██╗ ██╔╝██║  ██║██║  ██║ │"
    echo "│ ██║  ██║██║  ██║███████║╚██████╔╝███████╗╚██████╔╝ ╚████╔╝ ██████╔╝██████╔╝ │"
    echo "│ ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝   ╚═══╝  ╚═════╝ ╚═════╝  │"
    echo "└─────────────────────────────────────────────────────────────────────────────┘"
    echo "useradd by rasulovdd"
    echo "Проект: https://github.com/rasulovdd/useradd"
    echo "Контакты: @RasulovDD"
    echo ""
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} $1"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

print_step() {
    echo -e "\n${MAGENTA}➜${NC} $1"
}

# =============================================================================
# ФУНКЦИИ КОНФИГУРАЦИИ
# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Этот скрипт должен запускаться с правами root!"
        echo "Используйте: sudo $0"
        exit 1
    fi
}

get_domain_input() {
    print_header "НАСТРОЙКА ДОМЕНОВ"
    
    echo -e "\n${YELLOW}Шаг 1 из 2: Основной домен для сайта-заглушки${NC}"
    echo "Примеры: example.com, mysite.org, vpn-service.net"
    echo ""
    
    while true; do
        read -p "Введите ваш основной домен (без http://): " DOMAIN
        
        # Проверка ввода
        if [[ -z "$DOMAIN" ]]; then
            print_error "Домен не может быть пустым!"
            continue
        fi
        
        if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "Некорректный формат домена! Пример: example.com"
            continue
        fi
        
        # Подтверждение
        echo -e "\nВы ввели: ${GREEN}$DOMAIN${NC}"
        read -p "Это правильно? [Y/n]: " confirm
        
        if [[ -z "$confirm" ]] || [[ "$confirm" =~ ^[Yy]$ ]]; then
            break
        fi
    done
    
    # Устанавливаем путь к SSL сертификатам
    SSL_CERT_PATH="/etc/letsencrypt/live/$DOMAIN"
    
    show_vpn_domains_info
}

show_vpn_domains_info() {
    print_step "Шаг 2 из 2: Настройка VPN поддоменов"
    
    echo -e "\n${CYAN}Информация о VPN поддоменах:${NC}"
    echo "────────────────────────────────────────────"
    echo "Для работы VPN вам нужно настроить поддомены."
    echo "Примеры поддоменов для $DOMAIN:"
    echo "  • vpn1.$DOMAIN"
    echo "  • vpn2.$DOMAIN"
    echo "  • server.$DOMAIN"
    echo "  • proxy.$DOMAIN"
    echo ""
    echo "Скрипт создаст для каждого поддомена отдельный VPN порт."
    echo ""
    
    echo -e "${YELLOW}ВАЖНО:${NC}"
    echo "1. Создайте DNS A записи для этих поддоменов"
    echo "2. После установки настройте VPN сервисы на указанных портах"
    
    setup_vpn_domains
}

setup_vpn_domains() {
    echo -e "\n${CYAN}Настройка VPN поддоменов:${NC}"
    
    # Предлагаем варианты по умолчанию
    default_vpns=("vpn1.$DOMAIN" "vpn2.$DOMAIN" "vpn3.$DOMAIN")
    
    echo -e "\nСкрипт создаст ${GREEN}3 поддомена${NC} по умолчанию:"
    for vpn in "${default_vpns[@]}"; do
        echo "  • $vpn"
    done
    
    echo ""
    read -p "Использовать поддомены по умолчанию? [Y/n]: " use_default
    
    if [[ -z "$use_default" ]] || [[ "$use_default" =~ ^[Yy]$ ]]; then
        VPN_DOMAINS=("${default_vpns[@]}")
        print_status "Используются поддомены по умолчанию"
    else
        get_custom_vpn_domains
    fi
    
    show_domain_summary
}

get_custom_vpn_domains() {
    echo -e "\n${CYAN}Введите ваши VPN поддомены:${NC}"
    echo "(вводите по одному, пустая строка - завершение ввода)"
    echo ""
    
    local count=0
    while true; do
        local vpn_number=$((count + 1))
        read -p "Поддомен #$vpn_number (или Enter для завершения): " vpn_domain
        
        if [[ -z "$vpn_domain" ]]; then
            if [[ $count -eq 0 ]]; then
                print_error "Нужно указать хотя бы один поддомен!"
                continue
            else
                break
            fi
        fi
        
        # Проверка формата
        if [[ ! "$vpn_domain" =~ ^[a-zA-Z0-9][a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            print_error "Некорректный формат домена! Пример: vpn1.$DOMAIN"
            continue
        fi
        
        VPN_DOMAINS+=("$vpn_domain")
        count=$((count + 1))
        
        if [[ $count -ge 10 ]]; then
            print_warning "Достигнут лимит 10 поддоменов"
            break
        fi
    done
}

show_domain_summary() {
    print_header "СВОДКА КОНФИГУРАЦИИ"
    
    echo -e "${CYAN}Основной домен (сайт):${NC}"
    echo "  ${GREEN}https://$DOMAIN${NC}"
    
    echo -e "\n${CYAN}VPN поддомены:${NC}"
    local i=1
    for vpn_domain in "${VPN_DOMAINS[@]}"; do
        local port=$((5442 + i))
        echo "  $i. $vpn_domain → порт: $port"
        i=$((i + 1))
    done
    
    echo -e "\n${CYAN}Порты для настройки:${NC}"
    echo "  443  → HAProxy (весь трафик)"
    echo "  8443 → Nginx (сайт)"
    echo "  8404 → Статистика HAProxy"
    
    echo -e "\n${YELLOW}⚠️  ВАЖНО: Перед установкой убедитесь, что:${NC}"
    echo "1. Домен $DOMAIN указывает на этот сервер"
    echo "2. Вы готовы создать DNS записи для VPN поддоменов"
    echo "3. Вы настроите VPN сервисы на указанных портах"
    
    echo ""
    read -p "Продолжить установку? [Y/n]: " confirm
    
    if [[ -n "$confirm" ]] && [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Установка отменена"
        exit 0
    fi
}

save_config_to_file() {
    local config_file="/etc/HAProxy-Nginx.conf"
    
    cat > "$config_file" << EOF
# VPN Gateway Configuration
# Generated on $(date)

DOMAIN="$DOMAIN"
VPN_DOMAINS=($(printf "\"%s\" " "${VPN_DOMAINS[@]}"))
INSTALL_DATE="$(date)"
EOF
    
    chmod 600 "$config_file"
    print_info "Конфигурация сохранена в: $config_file"
}

# =============================================================================
# ФУНКЦИИ УСТАНОВКИ
# =============================================================================

install_all() {
    print_header "УСТАНОВКА ВСЕХ КОМПОНЕНТОВ"
    
    # Сохраняем конфигурацию
    save_config_to_file
    
    print_step "1. Обновление системы..."
    apt-get update && apt-get upgrade -y
    
    print_step "2. Установка HAProxy..."
    apt-get install -y haproxy
    
    print_step "3. Установка Nginx..."
    apt-get install -y nginx
    
    print_step "4. Установка зависимостей..."
    apt-get install -y git curl certbot python3-certbot-nginx
    
    print_step "5. Получение SSL сертификата..."
    get_ssl_certificate
    
    print_step "6. Установка static_page..."
    install_static_page
    
    print_step "7. Настройка HAProxy..."
    configure_haproxy
    
    print_step "8. Настройка Nginx..."
    configure_nginx
    
    print_step "9. Включение автозагрузки..."
    systemctl enable haproxy nginx
    
    print_step "10. Перезапуск служб..."
    restart_services
    
    print_header "УСТАНОВКА ЗАВЕРШЕНА"
    show_post_install_info
}

get_ssl_certificate() {
    if [ ! -d "$SSL_CERT_PATH" ]; then
        print_info "Попытка получения SSL сертификата для $DOMAIN..."
        
        # Проверяем, доступен ли домен
        print_info "Проверка доступности домена..."
        
        # Если домен указывает на сервер, пробуем получить сертификат
        if certbot certonly --nginx -d "$DOMAIN" -d "www.$DOMAIN" \
            --non-interactive --agree-tos --email "admin@$DOMAIN" 2>/dev/null; then
            print_status "SSL сертификат получен успешно!"
        else
            print_warning "Не удалось получить SSL сертификат автоматически"
            print_info "Возможные причины:"
            echo "  1. Домен $DOMAIN не указывает на этот сервер"
            echo "  2. Порт 80 закрыт или занят"
            echo "  3. Проблемы с DNS"
            echo ""
            print_info "Вы можете:"
            echo "  • Получить сертификат позже: certbot certonly --nginx -d $DOMAIN"
            echo "  • Использовать self-signed сертификат (скрипт продолжит установку)"
            echo ""
            read -p "Продолжить без SSL сертификата? [Y/n]: " ssl_continue
            
            if [[ -n "$ssl_continue" ]] && [[ ! "$ssl_continue" =~ ^[Yy]$ ]]; then
                print_error "Установка прервана. Настройте DNS и попробуйте снова."
                exit 1
            fi
        fi
    else
        print_status "SSL сертификат уже установлен"
    fi
}

install_static_page() {
    cd /var/www/html 2>/dev/null || mkdir -p /var/www/html && cd /var/www/html
    
    if [ -d "static_page" ]; then
        print_info "static_page уже существует, обновляем..."
        cd static_page
        git pull origin main
        cd ..
    else
        git clone $STATIC_PAGE_REPO
    fi
    
    # Создаем index.html если его нет
    if [ ! -f "/var/www/html/static_page/index.html" ]; then
        cat > /var/www/html/static_page/index.html << HTML
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to $DOMAIN</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 20px;
            line-height: 1.6;
        }
        .header {
            text-align: center;
            padding: 20px;
            background: #f4f4f4;
            border-radius: 5px;
            margin-bottom: 30px;
        }
        .info-box {
            background: #e8f4fc;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>Welcome to $DOMAIN</h1>
        <p>Site is under construction</p>
    </div>
    
    <div class="info-box">
        <h3>VPN Gateway Information</h3>
        <p><strong>Main Domain:</strong> $DOMAIN</p>
        <p><strong>VPN Subdomains:</strong></p>
        <ul>
$(for vpn in "${VPN_DOMAINS[@]}"; do
    echo "            <li>$vpn</li>"
done)
        </ul>
    </div>
    
    <p>This is a static page generated by HAProxy-Nginx Script.</p>
</body>
</html>
HTML
    fi
    
    chown -R www-data:www-data /var/www/html/static_page
    chmod -R 755 /var/www/html/static_page
    print_status "Static page установлена"
}

configure_haproxy() {
    # Создаем backup
    cp $HA_PROXY_CFG "$HA_PROXY_CFG.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Генерируем пароль для статистики
    STATS_PASSWORD=$(openssl rand -base64 12 | head -c 12)
    
    cat > $HA_PROXY_CFG << EOF
global
    log /dev/log local0
    maxconn 10000
    user haproxy
    group haproxy
    daemon
    tune.ssl.default-dh-param 2048

defaults
    log global
    mode tcp
    option tcplog
    option dontlognull
    timeout connect 5s
    timeout client 1m
    timeout server 1m
    timeout tunnel 1h
    retries 3

# Основной фронтенд на порту 443
frontend shared_443
    bind :443
    mode tcp
    
    tcp-request inspect-delay 5s
    tcp-request content accept if { req.ssl_hello_type 1 }
    
    # ACL для VPN доменов
$(for domain in "${VPN_DOMAINS[@]}"; do
    domain_id=$(echo "$domain" | tr '.-' '_')
    echo "    acl is_${domain_id} req.ssl_sni -i $domain"
done)
    
    # Маршрутизация VPN трафика
$(i=1
for domain in "${VPN_DOMAINS[@]}"; do
    domain_id=$(echo "$domain" | tr '.-' '_')
    echo "    use_backend backend_vpn$i if is_${domain_id}"
    i=$((i+1))
done)
    
    # Весь остальной трафик → Nginx (сайт)
    default_backend nginx_site

# Бэкенды для VPN
$(i=1
for domain in "${VPN_DOMAINS[@]}"; do
    port=$((5442 + i))
    cat << BACKEND
backend backend_vpn$i
    mode tcp
    balance leastconn
    option tcp-check
    timeout server 30m
    timeout connect 5s
    server vpn_backend$i 127.0.0.1:$port check
BACKEND
    i=$((i+1))
done)

# Бэкенд для Nginx (сайт)
backend nginx_site
    mode tcp
    option tcp-check
    timeout server 30s
    server nginx_local 127.0.0.1:8443 send-proxy-v2 check

# Статистика HAProxy
listen stats
    bind :8404
    stats enable
    stats uri /stats
    stats refresh 30s
    stats admin if TRUE
    stats hide-version
    stats auth admin:$STATS_PASSWORD
EOF
    
    print_status "Конфигурация HAProxy создана"
    print_info "Пароль для статистики: ${GREEN}$STATS_PASSWORD${NC}"
}

configure_nginx() {
    # Создаем backup
    cp $NGINX_SITE_CFG "$NGINX_SITE_CFG.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Проверяем наличие SSL сертификатов
    local ssl_cert=""
    local ssl_key=""
    
    if [ -d "$SSL_CERT_PATH" ] && [ -f "$SSL_CERT_PATH/fullchain.pem" ]; then
        ssl_cert="$SSL_CERT_PATH/fullchain.pem"
        ssl_key="$SSL_CERT_PATH/privkey.pem"
        print_status "Используются Let's Encrypt SSL сертификаты"
    else
        # Проверяем наличие self-signed сертификатов
        if [ -f "/etc/ssl/certs/ssl-cert-snakeoil.pem" ] && [ -f "/etc/ssl/private/ssl-cert-snakeoil.key" ]; then
            ssl_cert="/etc/ssl/certs/ssl-cert-snakeoil.pem"
            ssl_key="/etc/ssl/private/ssl-cert-snakeoil.key"
            print_warning "Используются self-signed SSL сертификаты"
        else
            # Создаем self-signed сертификат
            print_info "Создание self-signed SSL сертификата..."
            mkdir -p /etc/ssl/private
            openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                -keyout /etc/ssl/private/ssl-cert-snakeoil.key \
                -out /etc/ssl/certs/ssl-cert-snakeoil.pem \
                -subj "/C=US/ST=State/L=City/O=Organization/CN=$DOMAIN" 2>/dev/null
            ssl_cert="/etc/ssl/certs/ssl-cert-snakeoil.pem"
            ssl_key="/etc/ssl/private/ssl-cert-snakeoil.key"
        fi
    fi
    
    cat > $NGINX_SITE_CFG << EOF
# HTTP редирект
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    
    if (\$host = "$DOMAIN") {
        return 301 https://\$host\$request_uri;
    }
    
    return 404;
}

# Основной HTTPS сервер (для HAProxy)
server {
    listen 127.0.0.1:8443 ssl http2 proxy_protocol;
    server_name $DOMAIN www.$DOMAIN;
    
    # SSL сертификаты
    ssl_certificate $ssl_cert;
    ssl_certificate_key $ssl_key;
    
    # Настройки SSL
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    
    # Proxy Protocol
    real_ip_header proxy_protocol;
    set_real_ip_from 127.0.0.1;
    set_real_ip_from ::1;
    
    # Корневая директория
    root /var/www/html/static_page;
    index index.html;
    
    # Безопасность
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    
    # Статика
    location / {
        try_files \$uri \$uri/ =404;
    }
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)\$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    location ~ /\\. {
        deny all;
    }
}

# Резервный сервер (если HAProxy отключен)
server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;
    
    ssl_certificate $ssl_cert;
    ssl_certificate_key $ssl_key;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
    
    root /var/www/html/static_page;
    index index.html;
    
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    
    print_status "Конфигурация Nginx создана"
}

# =============================================================================
# ФУНКЦИИ УПРАВЛЕНИЯ
# =============================================================================

restart_services() {
    print_step "Перезапуск служб..."
    
    local errors=0
    
    # Проверка HAProxy
    if ! haproxy -c -f $HA_PROXY_CFG 2>/dev/null; then
        print_warning "Ошибка в конфигурации HAProxy"
        errors=$((errors + 1))
    else
        if systemctl restart haproxy 2>/dev/null; then
            print_status "HAProxy перезапущен"
        else
            print_warning "Не удалось перезапустить HAProxy"
            errors=$((errors + 1))
        fi
    fi
    
    # Проверка Nginx
    if ! nginx -t 2>/dev/null; then
        print_warning "Ошибка в конфигурации Nginx"
        errors=$((errors + 1))
    else
        if systemctl restart nginx 2>/dev/null; then
            print_status "Nginx перезапущен"
        else
            print_warning "Не удалось перезапустить Nginx"
            errors=$((errors + 1))
        fi
    fi
    
    if [[ $errors -eq 0 ]]; then
        print_status "Все службы успешно перезапущены"
    else
        print_warning "Были обнаружены ошибки. Проверьте конфигурацию."
    fi
}

show_post_install_info() {
    print_header "🎉 УСТАНОВКА ЗАВЕРШЕНА!"
    
    local server_ip=$(curl -s ifconfig.me 2>/dev/null || echo "ВАШ_IP_АДРЕС")
    
    echo -e "\n${GREEN}✅ Основные настройки:${NC}"
    echo "────────────────────────────────────────────"
    echo -e "Основной домен: ${CYAN}$DOMAIN${NC}"
    echo -e "Сервер IP: ${CYAN}$server_ip${NC}"
    
    echo -e "\n${YELLOW}📋 ЧТО СДЕЛАТЬ ДАЛЬШЕ:${NC}"
    echo "────────────────────────────────────────────"
    
    echo -e "\n${CYAN}1. НАСТРОЙТЕ DNS ЗАПИСИ:${NC}"
    echo "   Создайте A записи у вашего регистратора доменов:"
    echo "   • $DOMAIN → $server_ip"
    echo "   • www.$DOMAIN → $server_ip"
    
    local i=1
    for vpn_domain in "${VPN_DOMAINS[@]}"; do
        echo "   • $vpn_domain → $server_ip"
        i=$((i + 1))
    done
    
    echo -e "\n${CYAN}2. НАСТРОЙТЕ VPN СЕРВИСЫ:${NC}"
    echo "   Каждому VPN поддомену соответствует порт:"
    i=1
    for vpn_domain in "${VPN_DOMAINS[@]}"; do
        local port=$((5442 + i))
        echo "   • $vpn_domain → настройте VPN на порту $port"
        i=$((i + 1))
    done
    
    echo -e "\n${CYAN}3. ИЗМЕНИТЕ ПОДДОМЕНЫ В КОНФИГУРАЦИИ (ЕСЛИ НУЖНО):${NC}"
    echo "   Файл: ${YELLOW}/etc/haproxy/haproxy.cfg${NC}"
    echo "   Найдите строки с 'acl is_' и измените поддомены"
    echo "   Пример изменения:"
    echo "   Было: acl is_vpn1_your_domain_com req.ssl_sni -i vpn1.your-domain.com"
    echo "   Стало: acl is_my_real_vpn_domain req.ssl_sni -i real-vpn.domain.com"
    
    echo -e "\n${CYAN}4. ПРОВЕРЬТЕ РАБОТУ:${NC}"
    echo "   • Сайт: https://$DOMAIN"
    echo "   • Статистика: http://$server_ip:8404/stats"
    echo "   • VPN: подключитесь через клиент к вашему поддомену"
    
    echo -e "\n${CYAN}5. КОНФИГУРАЦИОННЫЕ ФАЙЛЫ:${NC}"
    echo "   • HAProxy: /etc/haproxy/haproxy.cfg"
    echo "   • Nginx: /etc/nginx/sites-available/default"
    echo "   • Настройки: /etc/HAProxy-Nginx.conf"
    
    echo -e "\n${GREEN}🔧 КОМАНДЫ ДЛЯ УПРАВЛЕНИЯ:${NC}"
    echo "   sudo systemctl restart haproxy  # Перезапуск HAProxy"
    echo "   sudo systemctl restart nginx    # Перезапуск Nginx"
    echo "   sudo nginx -t                   # Проверка конфигурации Nginx"
    echo "   sudo haproxy -c -f /etc/haproxy/haproxy.cfg # Проверка HAProxy"
    
    echo -e "\n${RED}⚠️  ВАЖНОЕ ЗАМЕЧАНИЕ:${NC}"
    echo "Если вы использовали временные поддомены (vpn1.$DOMAIN и т.д.),"
    echo "ОБЯЗАТЕЛЬНО замените их на реальные в конфигурации HAProxy!"
    echo "Файл для редактирования: ${YELLOW}/etc/haproxy/haproxy.cfg${NC}"
    
    echo -e "\n${GREEN}🎯 СХЕМА РАБОТЫ:${NC}"
    echo "   Клиенты → Порт 443 → HAProxy →"
    echo "     • Если поддомен из списка VPN → соответствующий порт (5443+)"
    echo "     • Если другой домен → Nginx (8443) → сайт-заглушка"
    
    echo -e "\n${YELLOW}⏰ Примерное время настройки DNS: 5-30 минут${NC}"
    
    echo -e "\n────────────────────────────────────────────"
    print_status "Установка завершена успешно!"
    echo "Если возникли проблемы, проверьте логи:"
    echo "tail -f /var/log/haproxy.log"
    echo "tail -f /var/log/nginx/error.log"
}

# =============================================================================
# ОСНОВНОЕ МЕНЮ
# =============================================================================

show_main_menu() {
    clear
    print_header "HAProxy-Nginx"
    
    if [[ -n "$DOMAIN" ]]; then
        echo -e "${CYAN}Текущая конфигурация:${NC}"
        echo -e "Основной домен: ${GREEN}$DOMAIN${NC}"
        echo -e "VPN поддоменов: ${GREEN}${#VPN_DOMAINS[@]}${NC}"
        echo ""
    else
        echo -e "${YELLOW}Конфигурация не задана${NC}"
        echo "Сначала выберите опцию 1 для настройки доменов"
        echo ""
    fi
    
    echo -e "${CYAN}Выберите действие:${NC}"
    echo "────────────────────────────────────────────"
    echo "1. Настроить домены (обязательно сначала!)"
    echo "2. Установить ВСЕ компоненты"
    echo "3. Установить только Nginx + static_page"
    echo "4. Показать информацию о конфигурации"
    echo "5. Проверить статус служб"
    echo "6. Перезапустить службы"
    echo "7. Удалить ВСЕ компоненты"
    echo "0. Выход"
    echo "────────────────────────────────────────────"
    echo -n "Ваш выбор [0-7]: "
}

main() {
    check_root
    
    print_header "HAProxy-Nginx SCRIPT"
    echo -e "${GREEN}Версия 2.0${NC}"
    echo ""
    echo "Этот скрипт автоматически настроит:"
    echo "• HAProxy для SNI-маршрутизации VPN трафика"
    echo "• Nginx для сайта-заглушки"
    echo "• Полную инфраструктуру на порту 443"
    echo ""
    echo "Перед началом убедитесь, что:"
    echo "✓ У вас есть домен"
    echo "✓ Домен указывает на IP этого сервера"
    echo "✓ У вас есть права root"
    echo ""
    read -p "Нажмите Enter для продолжения..."
    
    while true; do
        show_main_menu
        read -r choice
        
        case $choice in
            1)
                get_domain_input
                ;;
            2)
                if [[ -z "$DOMAIN" ]]; then
                    print_error "Сначала настройте домены (опция 1)!"
                    sleep 2
                    continue
                fi
                install_all
                echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
                read -r
                ;;
            3)
                if [[ -z "$DOMAIN" ]]; then
                    print_error "Сначала настройте домены (опция 1)!"
                    sleep 2
                    continue
                fi
                install_nginx_only
                echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
                read -r
                ;;
            4)
                if [[ -z "$DOMAIN" ]]; then
                    print_error "Сначала настройте домены (опция 1)!"
                    sleep 2
                    continue
                fi
                show_post_install_info
                echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
                read -r
                ;;
            5)
                check_services_status
                echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
                read -r
                ;;
            6)
                restart_services
                echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
                read -r
                ;;
            7)
                echo -e "\n${RED}ВНИМАНИЕ: Это удалит ВСЕ компоненты!${NC}"
                read -p "Вы уверены? [y/N]: " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    remove_all
                fi
                echo -e "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
                read -r
                ;;
            0)
                print_status "Выход из программы"
                exit 0
                ;;
            *)
                print_error "Неверный выбор! Используйте цифры 0-7"
                sleep 2
                ;;
        esac
    done
}

# Функция удаления (простая версия)
remove_all() {
    print_header "УДАЛЕНИЕ КОМПОНЕНТОВ"
    
    systemctl stop haproxy 2>/dev/null
    systemctl stop nginx 2>/dev/null
    
    apt-get purge -y haproxy nginx nginx-common certbot python3-certbot-nginx 2>/dev/null
    apt-get autoremove -y 2>/dev/null
    
    rm -rf /etc/haproxy /etc/nginx /var/www/html/static_page /etc/HAProxy-Nginx.conf 2>/dev/null
    
    print_status "Все компоненты удалены"
}

# Функция проверки статуса служб
check_services_status() {
    print_header "СТАТУС СЛУЖБ"
    
    echo -e "\n${CYAN}Состояние служб:${NC}"
    echo "────────────────────────────────────────────"
    
    if systemctl is-active --quiet haproxy 2>/dev/null; then
        echo -e "HAProxy: ${GREEN}✓ запущен${NC}"
    else
        echo -e "HAProxy: ${RED}✗ остановлен${NC}"
    fi
    
    if systemctl is-active --quiet nginx 2>/dev/null; then
        echo -e "Nginx:   ${GREEN}✓ запущен${NC}"
    else
        echo -e "Nginx:   ${RED}✗ остановлен${NC}"
    fi
    
    echo -e "\n${CYAN}Прослушиваемые порты:${NC}"
    echo "────────────────────────────────────────────"
    ss -tulpn | grep -E ':(443|80|8443|8404)' | head -20 || echo "Нет активных подключений"
}

# Функция установки только Nginx (упрощенная)
install_nginx_only() {
    print_header "УСТАНОВКА NGINX + STATIC_PAGE"
    
    apt-get update
    apt-get install -y nginx
    install_static_page
    configure_nginx_for_standalone
    systemctl enable nginx
    systemctl restart nginx
    
    print_status "Nginx установлен и настроен"
    echo -e "\nСайт доступен по адресу: ${GREEN}https://$DOMAIN${NC}"
}

# Упрощенная конфигурация Nginx для standalone режима
configure_nginx_for_standalone() {
    # Проверяем SSL сертификаты
    local ssl_cert=""
    local ssl_key=""
    
    if [ -d "$SSL_CERT_PATH" ] && [ -f "$SSL_CERT_PATH/fullchain.pem" ]; then
        ssl_cert="$SSL_CERT_PATH/fullchain.pem"
        ssl_key="$SSL_CERT_PATH/privkey.pem"
    else
        ssl_cert="/etc/ssl/certs/ssl-cert-snakeoil.pem"
        ssl_key="/etc/ssl/private/ssl-cert-snakeoil.key"
    fi
    
    cat > $NGINX_SITE_CFG << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;

    if (\$host = "$DOMAIN") {
        return 301 https://\$host\$request_uri;
    }

    return 404;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN www.$DOMAIN;

    ssl_certificate $ssl_cert;
    ssl_certificate_key $ssl_key;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305';
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;

    root /var/www/html/static_page;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
}

# Запуск скрипта
main