#!/usr/bin/env bash
# AmneziaWG UDP forwarder via socat
# Installer & management script
# Repository: github.com/uristdobra/AmneziaWG-socat-forwarder

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
        # Если не root, перезапустить с sudo
        exec sudo "$0" "$@"
    fi
}

press_enter() {
    read -rp "Нажмите Enter для продолжения..." _
}

install_self() {
    echo -e "${yellow}⚙️  Установка глобальной команды 'menu'...${plain}"
    mkdir -p "${SCRIPT_DIR}"
    cp "$0" "${SCRIPT_PATH}"
    chmod +x "${SCRIPT_PATH}"

    cat > "/usr/local/bin/menu" <<'EOF'
#!/usr/bin/env bash
if [[ $EUID -ne 0 ]]; then
    exec sudo /opt/amneziawg-forwarder/install.sh menu
fi
exec /opt/amneziawg-forwarder/install.sh menu
EOF
    chmod +x "/usr/local/bin/menu"

    echo -e "${green}✅ Глобальная команда 'menu' установлена!${plain}"
    echo -e "Используйте: ${yellow}menu${plain}"
}

uninstall_self() {
    echo -e "${yellow}Удаление глобальной команды 'menu'...${plain}"
    rm -f "/usr/local/bin/menu"
    echo -e "${green}✅ Глобальная команда удалена.${plain}"
}

install_forwarder() {
    echo -e "${blue}=== Создание каскадного VPN AmneziaWG ===${plain}"
    echo
    echo -e "${yellow}📦 Шаг 1. Обновление пакетов и установка утилит...${plain}"
    apt update && apt upgrade -y
    apt install -y curl wget socat

    echo -e "${green}✅ Пакеты установлены${plain}"
    echo

    echo -e "${yellow}🔧 Шаг 2. Параметры зарубежного VPN-сервера.${plain}"
    echo "Используйте данные из конфигурации AmneziaWG (Endpoint):"
    echo
    read -rp "  IP зарубежного сервера: " REMOTE_IP
    read -rp "  UDP-порт сервера: " REMOTE_PORT

    if [[ -z "$REMOTE_IP" || -z "$REMOTE_PORT" ]]; then
        echo -e "${red}❌ IP и порт обязательны. Установка отменена.${plain}"
        exit 1
    fi

    echo -e "${green}✅ Параметры получены${plain}"
    echo

    echo -e "${yellow}📄 Шаг 3. Создание systemd-службы ${SERVICE_NAME}.service...${plain}"
    cat > "${SERVICE_FILE}" <<EOFSERVICE
[Unit]
Description=AmneziaWG UDP forwarder via socat
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat -T15 udp-recvfrom:${REMOTE_PORT},reuseaddr,fork udp-sendto:${REMOTE_IP}:${REMOTE_PORT}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSERVICE

    echo -e "${green}✅ Служба создана${plain}"
    echo

    echo -e "${yellow}🚀 Шаг 4. Активация и запуск службы...${plain}"
    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}.service"
    systemctl restart "${SERVICE_NAME}.service"

    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        echo -e "${green}✅ Служба успешно запущена!${plain}"
    else
        echo -e "${red}⚠️  Ошибка при запуске службы. Проверьте:${plain}"
        echo -e "${yellow}sudo systemctl status wg-forward.service${plain}"
        exit 1
    fi

    echo
    echo -e "${blue}╔══════════════════════════════════════════════════╗${plain}"
    echo -e "${blue}║${plain}  ${green}✅ VPN-форвардер успешно установлен!${plain}  ${blue}║${plain}"
    echo -e "${blue}╚══════════════════════════════════════════════════╝${plain}"
    echo
    echo -e "${yellow}📋 Следующие шаги:${plain}"
    echo -e "1. Откройте конфиг AmneziaWG на ${yellow}клиенте${plain}"
    echo -e "2. Замените IP в ${yellow}Endpoint${plain} на IP ${yellow}этого RU-сервера${plain}"
    echo -e "3. Оставьте ${yellow}тот же порт${plain}: ${green}${REMOTE_PORT}${plain}"
    echo
    echo -e "${yellow}💡 Используйте команду для управления:${plain} ${green}menu${plain}"
}

uninstall_forwarder() {
    echo -e "${blue}=== Удаление VPN-форвардера ===${plain}"
    echo -e "${yellow}⏹️  Остановка службы...${plain}"
    systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true

    echo -e "${yellow}🗑️  Удаление файла ${SERVICE_FILE}...${plain}"
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload

    echo -e "${green}✅ VPN-форвардер полностью удалён.${plain}"
}

start_forwarder() {
    echo -e "${blue}=== Запуск службы ${SERVICE_NAME} ===${plain}"
    systemctl start "${SERVICE_NAME}.service"
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        echo -e "${green}✅ Служба запущена.${plain}"
    else
        echo -e "${red}❌ Ошибка при запуске.${plain}"
    fi
}

stop_forwarder() {
    echo -e "${blue}=== Остановка службы ${SERVICE_NAME} ===${plain}"
    systemctl stop "${SERVICE_NAME}.service"
    echo -e "${green}✅ Служба остановлена.${plain}"
}

restart_forwarder() {
    echo -e "${blue}=== Перезапуск службы ${SERVICE_NAME} ===${plain}"
    systemctl restart "${SERVICE_NAME}.service"
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        echo -e "${green}✅ Служба перезапущена.${plain}"
    else
        echo -e "${red}❌ Ошибка при перезапуске.${plain}"
    fi
}

status_forwarder() {
    echo -e "${blue}=== Статус службы ${SERVICE_NAME} ===${plain}"
    systemctl status "${SERVICE_NAME}.service" --no-pager -l
}

show_menu() {
    clear
    echo -e "${blue}╔════════════════════ AmneziaWG socat FORWARDER ════════════════════╗${plain}"
    echo -e "${blue}║${plain}                                                                  ${blue}║${plain}"
    echo -e "${blue}║${plain}  ${green}1${plain} 🔧 Установить/переустановить форвардер${blue}                   ║${plain}"
    echo -e "${blue}║${plain}  ${green}2${plain} ▶️  Запустить службу${blue}                                    ║${plain}"
    echo -e "${blue}║${plain}  ${green}3${plain} ⏹️  Остановить службу${blue}                                   ║${plain}"
    echo -e "${blue}║${plain}  ${green}4${plain} 🔄 Перезапустить службу${blue}                                ║${plain}"
    echo -e "${blue}║${plain}  ${green}5${plain} 📊 Показать статус${blue}                                     ║${plain}"
    echo -e "${blue}║${plain}  ${green}6${plain} 🗑️  Удалить службу${blue}                                     ║${plain}"
    echo -e "${blue}║${plain}  ${green}0${plain} 👋 Выход${blue}                                              ║${plain}"
    echo -e "${blue}║${plain}                                                                  ${blue}║${plain}"
    echo -e "${blue}╚════════════════════════════════════════════════════════════════════╝${plain}"
    echo
    read -rp "Выбор (0-6): " num

    case "${num}" in
        1) install_forwarder ;;
        2) start_forwarder ;;
        3) stop_forwarder ;;
        4) restart_forwarder ;;
        5) status_forwarder ;;
        6) uninstall_forwarder ;;
        0) echo -e "${green}👋 До свидания!${plain}"; exit 0 ;;
        *) echo -e "${red}❌ Неверный выбор (введите 0-6).${plain}" ;;
    esac
    echo
    press_enter
}

# Проверка прав и перезапуск с sudo если нужно
check_root

case "${1}" in
    "menu")
        while true; do
            show_menu
        done
        ;;
    *)
        # При первом запуске без аргументов - сразу установка
        install_forwarder
        install_self
        ;;
esac
