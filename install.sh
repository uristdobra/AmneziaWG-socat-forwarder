#!/usr/bin/env bash
# AmneziaWG UDP forwarder via socat
# Installer & management script

SERVICE_NAME="wg-forward"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SCRIPT_DIR="/opt/amneziawg-forwarder"
SCRIPT_PATH="${SCRIPT_DIR}/install.sh"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[1;34m'
plain='\033[0m'

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${red}Запустите скрипт от root (через sudo).${plain}"
        exit 1
    fi
}

install_self() {
    echo -e "${yellow}Установка глобальной команды 'menu'...${plain}"
    mkdir -p "${SCRIPT_DIR}"
    cp "$0" "${SCRIPT_PATH}"
    chmod +x "${SCRIPT_PATH}"
    
    cat > "/usr/local/bin/menu" <<EOF
#!/usr/bin/env bash
exec sudo "${SCRIPT_PATH}" menu
EOF
    chmod +x "/usr/local/bin/menu"
    
    echo -e "${green}Глобальная команда 'menu' установлена!${plain}"
    echo "Теперь можно вызывать: menu"
}

uninstall_self() {
    echo -e "${yellow}Удаление глобальной команды 'menu'...${plain}"
    rm -f "/usr/local/bin/menu"
    rm -rf "${SCRIPT_DIR}"
    echo -e "${green}Глобальная команда удалена.${plain}"
}

press_enter() {
    read -rp "Нажмите Enter для продолжения..." _
}

install_forwarder() {
    echo -e "${blue}=== Создание каскадного VPN AmneziaWG ===${plain}"
    echo -e "${yellow}Шаг 1. Обновление пакетов и установка утилит...${plain}"
    apt update && apt upgrade -y
    apt install -y curl wget socat

    echo -e "${yellow}Шаг 2. Параметры зарубежного VPN-сервера.${plain}"
    echo "Данные из конфигурации AmneziaWG (Endpoint):"
    read -rp "IP зарубежного сервера: " REMOTE_IP
    read -rp "UDP-порт сервера: " REMOTE_PORT

    if [[ -z "$REMOTE_IP" || -z "$REMOTE_PORT" ]]; then
        echo -e "${red}IP и порт обязательны!${plain}"
        exit 1
    fi

    echo -e "${yellow}Шаг 3. Создание службы ${SERVICE_NAME}.service...${plain}"
    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=AmneziaWG UDP forwarder via socat
After=network.target

[Service]
ExecStart=/usr/bin/socat -T15 udp-recvfrom:${REMOTE_PORT},reuseaddr,fork udp-sendto:${REMOTE_IP}:${REMOTE_PORT}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${yellow}Шаг 4. Запуск службы...${plain}"
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.service"
    systemctl restart "${SERVICE_NAME}.service"

    echo -e "${green}✅ VPN-форвардер установлен и запущен!${plain}"
    echo -e "${blue}В конфиге AmneziaWG замените IP на IP этого RU-сервера, порт: ${REMOTE_PORT}${plain}"
}

uninstall_forwarder() {
    echo -e "${blue}=== Удаление VPN-форвардера ===${plain}"
    systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload
    echo -e "${green}✅ VPN-форвардер удален.${plain}"
}

start_forwarder() {
    echo -e "${blue}🚀 Запуск службы...${plain}"
    systemctl start "${SERVICE_NAME}.service"
    echo -e "${green}✅ Служба запущена.${plain}"
}

stop_forwarder() {
    echo -e "${blue}⏹️ Остановка службы...${plain}"
    systemctl stop "${SERVICE_NAME}.service"
    echo -e "${green}✅ Служба остановлена.${plain}"
}

restart_forwarder() {
    echo -e "${blue}🔄 Перезапуск службы...${plain}"
    systemctl restart "${SERVICE_NAME}.service"
    echo -e "${green}✅ Служба перезапущена.${plain}"
}

status_forwarder() {
    echo -e "${blue}📊 Статус службы:${plain}"
    systemctl status "${SERVICE_NAME}.service" --no-pager -l
}

show_menu() {
    clear
    echo -e "${blue}================ AmneziaWG socat FORWARDER ================${plain}"
    echo -e "${green}1.${plain} 🔧 Установить/переустановить форвардер"
    echo -e "${green}2.${plain} ▶️  Запустить службу"
    echo -e "${green}3.${plain} ⏹️  Остановить службу"
    echo -e "${green}4.${plain} 🔄 Перезапустить службу"
    echo -e "${green}5.${plain} 📊 Показать статус"
    echo -e "${green}6.${plain} 🗑️  Удалить службу"
    echo -e "${yellow}7.${plain} ⚙️  Установить команду 'menu'"
    echo -e "${yellow}8.${plain} ❌ Удалить команду 'menu'"
    echo -e "${green}0.${plain} 👋 Выход"
    echo "================================================================"
    read -rp "Выбор: " num

    case "${num}" in
        1) install_forwarder ;;
        2) start_forwarder ;;
        3) stop_forwarder ;;
        4) restart_forwarder ;;
        5) status_forwarder ;;
        6) uninstall_forwarder ;;
        7) install_self ;;
        8) uninstall_self ;;
        0) exit 0 ;;
        *) echo -e "${red}❌ Неверный выбор.${plain}" ;;
    esac
    echo
    press_enter
}

case "${1}" in
    "menu")
        check_root
        while true; do
            show_menu
        done
        ;;
    "установить")
        check_root
        install_forwarder
        ;;
    "стоп")
        check_root
        stop_forwarder
        ;;
    "старт")
        check_root
        start_forwarder
        ;;
    "рестарт")
        check_root
        restart_forwarder
        ;;
    "статус")
        check_root
        status_forwarder
        ;;
    "удалить")
        check_root
        uninstall_forwarder
        ;;
    *)
        echo -e "${blue}🎯 AmneziaWG UDP Forwarder${plain}"
        echo "Использование:"
        echo "  sudo $0 menu     — меню управления"
        echo "  sudo $0 установить — установка"
        echo "Или после установки команды:"
        echo "  menu             — **меню управления**"
        echo "  sudo systemctl status wg-forward.service"
        exit 1
        ;;
esac
