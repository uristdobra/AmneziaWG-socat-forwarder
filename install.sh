#!/usr/bin/env bash

SERVICE_NAME="wg-forward"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
SCRIPT_DIR="/opt/amneziawg-forwarder"
GITHUB_RAW="https://raw.githubusercontent.com/uristdobra/AmneziaWG-socat-forwarder/main/install.sh"

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[1;34m'
plain='\033[0m'

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${red}❌ Требуется запуск от root.${plain}"
        exit 1
    fi
}

install_base() {
    check_root

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
    systemctl start "${SERVICE_NAME}.service"

    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        echo -e "${green}✅ Служба успешно запущена!${plain}"
    else
        echo -e "${red}⚠️  Ошибка при запуске службы. Проверьте:${plain}"
        echo -e "${yellow}systemctl status ${SERVICE_NAME}.service${plain}"
        exit 1
    fi

    echo
    echo -e "${yellow}📄 Шаг 5. Установка команды 'menu'...${plain}"
    mkdir -p "${SCRIPT_DIR}"

    # Попытка корректно получить путь до текущего файла
    SRC="${BASH_SOURCE[0]}"

    if [[ -f "$SRC" ]]; then
        cp -- "$SRC" "${SCRIPT_DIR}/install.sh"
    else
        # Если запущено как curl | bash — скачиваем оригинал с GitHub
        echo -e "${yellow}⚠️  Локальный файл не определён, скачиваю оригинал с GitHub...${plain}"
        mkdir -p "${SCRIPT_DIR}"
        if ! curl -fsSL "${GITHUB_RAW}" -o "${SCRIPT_DIR}/install.sh"; then
            echo -e "${red}❌ Не удалось скачать install.sh с GitHub. Установка не завершена.${plain}"
            exit 1
        fi
    fi

    chmod +x "${SCRIPT_DIR}/install.sh"

    # Устанавливаем простой wrapper без sudo (чтобы не менять контекст запуска)
    cat > "/usr/local/bin/menu" <<'EOFMENU'
#!/bin/bash
# wrapper for AmneziaWG forwarder menu
exec /opt/amneziawg-forwarder/install.sh menu
EOFMENU
    chmod +x "/usr/local/bin/menu"

    echo -e "${green}✅ Команда 'menu' установлена!${plain}"
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

start_service() {
    check_root
    echo -e "${blue}=== Запуск службы ${SERVICE_NAME} ===${plain}"
    systemctl start "${SERVICE_NAME}.service"
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        echo -e "${green}✅ Служба запущена.${plain}"
    else
        echo -e "${red}❌ Ошибка при запуске.${plain}"
    fi
}

stop_service() {
    check_root
    echo -e "${blue}=== Остановка службы ${SERVICE_NAME} ===${plain}"
    systemctl stop "${SERVICE_NAME}.service"
    echo -e "${green}✅ Служба остановлена.${plain}"
}

restart_service() {
    check_root
    echo -e "${blue}=== Перезапуск службы ${SERVICE_NAME} ===${plain}"
    systemctl restart "${SERVICE_NAME}.service"
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        echo -e "${green}✅ Служба перезапущена.${plain}"
    else
        echo -e "${red}❌ Ошибка при перезапуске.${plain}"
    fi
}

status_service() {
    echo -e "${blue}=== Статус службы ${SERVICE_NAME} ===${plain}"
    systemctl status "${SERVICE_NAME}.service" --no-pager -l
}

uninstall_service() {
    check_root
    echo -e "${blue}=== Удаление VPN-форвардера ===${plain}"
    echo -e "${yellow}⏹️  Остановка службы...${plain}"
    systemctl stop "${SERVICE_NAME}.service" 2>/dev/null || true
    systemctl disable "${SERVICE_NAME}.service" 2>/dev/null || true

    echo -e "${yellow}🗑️  Удаление файла ${SERVICE_FILE}...${plain}"
    rm -f "${SERVICE_FILE}"
    systemctl daemon-reload

    echo -e "${green}✅ VPN-форвардер полностью удалён.${plain}"
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
        1) install_base ;;
        2) start_service ;;
        3) stop_service ;;
        4) restart_service ;;
        5) status_service ;;
        6) uninstall_service ;;
        0) echo -e "${green}👋 До свидания!${plain}"; exit 0 ;;
        *) echo -e "${red}❌ Неверный выбор (введите 0-6).${plain}" ;;
    esac

    echo
    read -rp "Нажмите Enter для продолжения..." _
}

main() {
    case "$1" in
        menu)
            check_root
            while true; do
                show_menu
            done
            ;;
        *)
            check_root
            install_base
            ;;
    esac
}

main "$@"
