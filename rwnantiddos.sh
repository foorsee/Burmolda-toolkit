#!/bin/bash

# ==============================================================================
# Remnanode Interactive Protection & Tuning Script (Menu Edition)
# ==============================================================================

# Цветовая палитра
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

LOG_FILE="/tmp/remnanode_install.log"
USER_IP=$(curl -s ifconfig.me)

# Массивы стран
COUNTRY_CODES=("CN" "IN" "BR" "PK" "VN" "TW" "BD" "ID" "IR" "ZA" "MX" "EC")
COUNTRY_RU=("Китай" "Индия" "Бразилия" "Пакистан" "Вьетнам" "Тайвань" "Бангладеш" "Индонезия" "Иран" "Южная Африка" "Мексика" "Эквадор")

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Запустите скрипт через sudo!${NC}"
  exit 1
fi

# ==========================================
# Анимация Звезды Давида
# ==========================================
spin_david_star() {
    local pid=$1
    local delay=0.15
    
    tput civis
    echo -e "\n\n\n\n\n\n\n"
    
    while kill -0 $pid 2>/dev/null; do
        tput cuu 7
        echo -e "${BLUE}       /\\       ${NC}"
        echo -e "${BLUE}    __/  \\__    ${NC}"
        echo -e "${BLUE}    \\  |   /    ${NC}"
        echo -e "${BLUE}    /_ |  _\\    ${NC}"
        echo -e "${BLUE}      \\  /      ${NC}"
        echo -e "${BLUE}       \\/       ${NC}"
        echo -e "${YELLOW} Выполнение задачи...   ${NC}"
        sleep $delay
        
        tput cuu 7
        echo -e "${BLUE}       /\\       ${NC}"
        echo -e "${BLUE}    __/ / \\__   ${NC}"
        echo -e "${BLUE}    \\    / /    ${NC}"
        echo -e "${BLUE}    /_ /  _\\    ${NC}"
        echo -e "${BLUE}      \\  /      ${NC}"
        echo -e "${BLUE}       \\/       ${NC}"
        echo -e "${YELLOW} Выполнение задачи..    ${NC}"
        sleep $delay
        
        tput cuu 7
        echo -e "${BLUE}       /\\       ${NC}"
        echo -e "${BLUE}    __/   \\__   ${NC}"
        echo -e "${BLUE}    \\ ---  /    ${NC}"
        echo -e "${BLUE}    /_   _\\     ${NC}"
        echo -e "${BLUE}      \\  /      ${NC}"
        echo -e "${BLUE}       \\/       ${NC}"
        echo -e "${YELLOW} Выполнение задачи.     ${NC}"
        sleep $delay
        
        tput cuu 7
        echo -e "${BLUE}       /\\       ${NC}"
        echo -e "${BLUE}    __\\   \\__   ${NC}"
        echo -e "${BLUE}    \\  \\   /    ${NC}"
        echo -e "${BLUE}    /_  \\ _\\    ${NC}"
        echo -e "${BLUE}      \\  /      ${NC}"
        echo -e "${BLUE}       \\/       ${NC}"
        echo -e "${YELLOW} Выполнение задачи      ${NC}"
        sleep $delay
    done
    
    tput cnorm
}

# ==========================================
# Логика запуска в фоне + проверка ошибок
# ==========================================
run_with_loader() {
    local cmd="$1"
    
    # Очищаем старый лог
    > "$LOG_FILE"
    
    eval "$cmd" > "$LOG_FILE" 2>&1 &
    local cmd_pid=$!
    
    spin_david_star $cmd_pid
    wait $cmd_pid
    local exit_status=$?
    
    if [ $exit_status -ne 0 ]; then
        echo -e "\n${RED}[ОШИБКА] Процесс завершился с кодом: $exit_status${NC}"
        echo -e "${YELLOW}--- Вывод последних 50 строк лога ---${NC}"
        tail -n 50 "$LOG_FILE"
        echo -e "${YELLOW}-------------------------------------${NC}"
        read -p "Нажмите Enter для продолжения..."
        return 1
    else
        echo -e "\n${GREEN}[УСПЕШНО] Операция выполнена!${NC}"
        sleep 1
        return 0
    fi
}

# ==========================================
# Рабочие функции для сайлент-мода
# ==========================================
setup_ufw() {
    ufw --force reset
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow $1/tcp comment 'SSH'
    ufw allow 80/tcp comment 'HTTP'
    ufw allow 443/tcp comment 'HTTPS'
    ufw allow $2 comment 'VPN/Xray'
    ufw --force enable
}

setup_network() {
    sed -i '/disable_ipv6/d' /etc/sysctl.conf
    sed -i '/default_qdisc/d' /etc/sysctl.conf
    sed -i '/tcp_congestion_control/d' /etc/sysctl.conf

    cat >> /etc/sysctl.conf << EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.core.default_qdisc = cake
net.ipv4.tcp_congestion_control = bbr
EOF
    sysctl -p
}

setup_traffic_guard() {
    curl -fsSL https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh | bash
    sudo traffic-guard full \
  -u https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list \
  -u https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list \
  --enable-logging
}

setup_geoblock() {
    local user_ip=$1
    shift
    local countries=("$@")

    ipset create geo_block hash:net maxelem 500000 -exist
    ipset flush geo_block
    iptables -I INPUT -s $user_ip -j ACCEPT

    for code in "${countries[@]}"; do
        curl -s "https://www.ipdeny.com/ipblocks/data/countries/$(echo $code | tr '[:upper:]' '[:lower:]').zone" | while read ip; do
            ipset add geo_block $ip -exist
        done
    done

    iptables -D INPUT -m set --match-set geo_block src -j DROP 2>/dev/null
    iptables -I INPUT -m set --match-set geo_block src -j DROP
}

# Предварительная установка базовых пакетов
echo -e "${YELLOW}Установка базовых зависимостей...${NC}"
apt update -q >/dev/null 2>&1
apt install -yq ufw curl ipset iptables speedtest-cli >/dev/null 2>&1

# ==========================================
# Главное меню
# ==========================================
while true; do
    clear
    echo -e "${BLUE}${BOLD}====================================================${NC}"
    echo -e "${BLUE}${BOLD}   Remnanode Security & Network Setup               ${NC}"
    echo -e "${BLUE}${BOLD}   Ваш IP: ${USER_IP}                               ${NC}"
    echo -e "${BLUE}${BOLD}====================================================${NC}"
    echo "1. Настроить сетевой экран (UFW)"
    echo "2. Оптимизация сети (Отключить IPv6, включить BBR+CAKE)"
    echo "3. Установить защиту от сканеров (Traffic-Guard)"
    echo "4. Настроить Гео-блокировку DDoS"
    echo "5. Запустить Speedtest"
    echo "0. Выход"
    echo -e "${BLUE}${BOLD}====================================================${NC}"
    read -p "Выберите действие [0-5]: " choice
    
    case $choice in
        1)
            echo -n -e "${YELLOW}Введите ваш текущий SSH порт: ${NC}"
            read SSH_PORT
            echo -n -e "${YELLOW}Введите порт вашего VPN/VLESS: ${NC}"
            read VPN_PORT
            run_with_loader "setup_ufw $SSH_PORT $VPN_PORT"
            ;;
        2)
            run_with_loader "setup_network"
            ;;
        3)
            run_with_loader "setup_traffic_guard"
            ;;
        4)
            echo -e "\n${BOLD}Доступные страны для блокировки:${NC}"
            for i in "${!COUNTRY_CODES[@]}"; do
                num=$((i+1))
                echo -e "  ${BOLD}${num})${NC} ${COUNTRY_CODES[$i]} - ${COUNTRY_RU[$i]}"
            done
            echo -e "${YELLOW}Введите номера через пробел (например: 1 3 5) или 'all':${NC}"
            read GEO_CHOICE

            SELECTED_CODES=()
            if [[ "$GEO_CHOICE" == "all" || "$GEO_CHOICE" == "ALL" ]]; then
                SELECTED_CODES=("${COUNTRY_CODES[@]}")
            else
                for num in $GEO_CHOICE; do
                    index=$((num-1))
                    if [[ $index -ge 0 && $index -lt ${#COUNTRY_CODES[@]} ]]; then
                        SELECTED_CODES+=("${COUNTRY_CODES[$index]}")
                    fi
                done
            fi

            if [ ${#SELECTED_CODES[@]} -gt 0 ]; then
                # Передаем IP и массив стран в функцию
                run_with_loader "setup_geoblock $USER_IP ${SELECTED_CODES[*]}"
            else
                echo -e "${RED}Страны не выбраны, пропускаем.${NC}"
                sleep 1
            fi
            ;;
        5)
            # Для спидтеста мы запускаем его через лоадер, а потом выводим результат
            run_with_loader "speedtest-cli --simple"
            if [ $? -eq 0 ]; then
                echo -e "\n${BLUE}--- Результаты Speedtest ---${NC}"
                cat "$LOG_FILE"
                echo -e "${BLUE}----------------------------${NC}"
                read -p "Нажмите Enter для продолжения..."
            fi
            ;;
        0)
            echo -e "${GREEN}Выход...${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный пункт меню!${NC}"
            sleep 1
            ;;
    esac
done