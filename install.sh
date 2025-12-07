#!/usr/bin/env bash
set -o errexit
set -o nounset
set -o pipefail

# Переработанный install.sh для AmneziaWG socat forwarder
# Поддерживает: установка, управление службой, меню и полную очистку (пункт 7)
#
# Установка: запустить от root:
#   sudo bash install.sh
#
# Меню можно вызвать командой `menu` после установки.
#
# Файл создаёт копию себя в /opt/amneziawg-forwarder/install.sh и устанавливает /usr/local/bin/menu
# P.S. Чтобы удалить текущий файл install.sh (тот, который вы запустили),
# используйте rm -f ./install.sh вручную после выполнения full_cleanup,
# т.к. процесс не может удалить сам себя во время исполнения.

SERVICE_NAME="wg-forward"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
INSTALL_DIR="/opt/amneziawg-forwarder"
INSTALLED_SCRIPT="${INSTALL_DIR}/install.sh"
MENU_BIN="/usr/local/bin/menu"
GITHUB_RAW="https://raw.githubusercontent.com/uristdobra/AmneziaWG-socat-forwarder/main/install.sh"

# Цвета
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[1;33m'
blue='\033[1;34m'
plain='\033[0m'

# -------------------------
# Утилиты
# -------------------------
log()   { echo -e "${green}$*${plain}"; }
warn()  { echo -e "${yellow}$*${plain}"; }
error() { echo -e "${red}$*${plain}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Требуется запуск от root. Повторите с sudo."
        exit 1
    fi
}

ensure_dir() {
    local d="$1"
    if [[ ! -d "$d" ]]; then
        mkdir -p "$d"
    fi
}

# Попытка корректно определить путь до текущего сценария
resolve_self_path() {
    # Возвращает абсолютный путь к текущему скрипту
    local src="${BASH_SOURCE[0]}"
    while [ -h "$src" ]; do
        local dir
        dir="$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
        src="$(readlink "$src")"
        [[ $src != /* ]] && src="$dir/$src"
    done
    echo "$(cd -P "$(dirname "$src")" >/dev/null 2>&1 && pwd)/$(basename "$src")"
}

# -------------------------
# Служба systemd
# -------------------------
create_service_file() {
    cat >"${SERVICE_FILE}" <<'EOFSERVICE'
[Unit]
Description=AmneziaWG socat forwarder
After=network.target

[Service]
Type=simple
ExecStart=/opt/amneziawg-forwarder/run-forwarder.sh
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOFSERVICE
    log "Сервисный файл создан: ${SERVICE_FILE}"
    systemctl daemon-reload || warn "Не удалось daemon-reload"
}

install_run_script() {
    ensure_dir "${INSTALL_DIR}"
    cat >"${INSTALL_DIR}/run-forwarder.sh" <<'EORUN'
#!/usr/bin/env bash
# Простой шаблон запуска socat/forwarder.
# TODO: здесь должно быть реальное содержимое запуска форвардера.
# Вместо этого оставляем заглушку, пользователь может заменить файл по необходимости.
echo "Запуск AmneziaWG forwarder (заглушка)."
sleep 3600
EORUN
    chmod +x "${INSTALL_DIR}/run-forwarder.sh"
    log "Установлен скрипт запуска: ${INSTALL_DIR}/run-forwarder.sh"
}

enable_and_start_service() {
    systemctl enable "${SERVICE_NAME}.service" || warn "Не удалось включить сервис"
    systemctl restart "${SERVICE_NAME}.service" || warn "Не удалось (пере)запустить сервис"
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        log "Служба ${SERVICE_NAME} активна."
    else
        warn "Служба ${SERVICE_NAME} не запущена. Проверьте systemctl status ${SERVICE_NAME}.service"
    fi
}

# -------------------------
# Установка меню
# -------------------------
install_menu_bin() {
    ensure_dir "$(dirname "${MENU_BIN}")"
    cat >"${MENU_BIN}" <<'EOMENU'
#!/usr/bin/env bash
# Утилита menu — вызывает скрипт установки/менеджера в /opt/amneziawg-forwarder
TARGET="/opt/amneziawg-forwarder/install.sh"
if [[ -x "$TARGET" ]]; then
    exec "$TARGET" --menu
else
    echo "Не найден ${TARGET}. Установите скрипт заново."
    exit 1
fi
EOMENU
    chmod +x "${MENU_BIN}"
    log "Установлена команда меню: ${MENU_BIN}"
}

# -------------------------
# Удаление/очистка
# -------------------------
remove_service_only() {
    check_root
    warn "Удаление службы ${SERVICE_NAME} (только служба)..."
    if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
        systemctl stop "${SERVICE_NAME}.service" || warn "Не удалось остановить сервис"
    fi
    systemctl disable "${SERVICE_NAME}.service" || warn "Не удалось отключить сервис"
    rm -f "${SERVICE_FILE}" || warn "Не удалось удалить ${SERVICE_FILE}"
    systemctl daemon-reload || warn "Не удалось daemon-reload"
    log "Служба удалена."
}

full_cleanup() {
    check_root
    warn "⚠️ Выполняется полная очистка: служба, файлы, меню..."
    # Останавливаем и удаляем сервис
    if systemctl list-units --full -all | grep -q "${SERVICE_NAME}.service"; then
        if systemctl is-active --quiet "${SERVICE_NAME}.service"; then
            systemctl stop "${SERVICE_NAME}.service" || warn "Не удалось остановить сервис"
        fi
        systemctl disable "${SERVICE_NAME}.service" || warn "Не удалось отключить сервис"
    fi
    rm -f "${SERVICE_FILE}" || true

    # Удаляем установленные файлы
    rm -rf "${INSTALL_DIR}" || warn "Не удалось удалить ${INSTALL_DIR}"
    rm -f "${MENU_BIN}" || warn "Не удалось удалить ${MENU_BIN}"

    # Если в /usr/local/bin есть альтернативные бинари, попробовать удалить
    rm -f /usr/local/bin/amneziawg-forwarder /usr/local/bin/amneziawg /usr/local/bin/amnezia-wg || true

    systemctl daemon-reload || warn "Не удалось daemon-reload"

    log "Полная очистка завершена."
    echo
    echo -e "${yellow}ℹ️ Если вы хотите удалить файл установщика, выполните вручную:${plain}"
    echo -e "  rm -f $(resolve_self_path)"
    echo
    log "Готово."
}

# -------------------------
# Основная логика установки
# -------------------------
install_forwarder() {
    check_root
    log "=== Шаг 1. Установка файлов форвардера ==="
    ensure_dir "${INSTALL_DIR}"

    # Скопируем этот исполняемый скрипт в INSTALL_DIR как install.sh, чтобы menu запускал именно его
    local self
    self="$(resolve_self_path)"
    cp -f "${self}" "${INSTALLED_SCRIPT}"
    chmod +x "${INSTALLED_SCRIPT}"
    log "Копия установщика сохранена в ${INSTALLED_SCRIPT}"

    # Установим run script и service
    install_run_script
    create_service_file
    enable_and_start_service

    # Установим меню
    install_menu_bin

    log "Установка завершена. Вызовите: menu для управления."
}

# -------------------------
# Управление службой
# -------------------------
start_service() {
    check_root
    log "Запуск службы..."
    systemctl start "${SERVICE_NAME}.service" || warn "Не удалось запустить сервис"
    systemctl status "${SERVICE_NAME}.service" --no-pager || true
}

stop_service() {
    check_root
    log "Остановка службы..."
    systemctl stop "${SERVICE_NAME}.service" || warn "Не удалось остановить сервис"
}

restart_service() {
    check_root
    log "Перезапуск службы..."
    systemctl restart "${SERVICE_NAME}.service" || warn "Не удалось перезапустить сервис"
    systemctl status "${SERVICE_NAME}.service" --no-pager || true
}

show_status() {
    systemctl status "${SERVICE_NAME}.service" --no-pager || true
    echo
    echo "Файлы:"
    ls -ld "${INSTALL_DIR}" "${SERVICE_FILE}" "${MENU_BIN}" 2>/dev/null || true
}

remove_service_interactive() {
    check_root
    read -rp "Вы уверены, что хотите удалить только службу? (y/N): " ans
    if [[ "${ans,,}" == "y" ]]; then
        remove_service_only
    else
        log "Отменено."
    fi
}

full_cleanup_interactive() {
    check_root
    echo -e "${red}ВНИМАНИЕ!${plain} Это удалит службу, каталог установки и команду menu."
    read -rp "Продолжить полную очистку? (y/N): " ans
    if [[ "${ans,,}" == "y" ]]; then
        full_cleanup
    else
        log "Отменено."
    fi
}

# -------------------------
# Меню
# -------------------------
show_menu() {
    while true; do
        clear
        echo -e "${blue}╔════════════════════ AmneziaWG socat FORWARDER ════════════════════╗${plain}"
        echo -e "${blue}║${plain}                                                                  ${blue}║${plain}"
        echo -e "${blue}║${plain}  ${green}1${plain} 🔧 Установить/переустановить форвардер${blue}                   ║${plain}"
        echo -e "${blue}║${plain}  ${green}2${plain} ▶️  Запустить службу${blue}                                    ║${plain}"
        echo -e "${blue}║${plain}  ${green}3${plain} ⏹️  Остановить службу${blue}                                   ║${plain}"
        echo -e "${blue}║${plain}  ${green}4${plain} 🔄 Перезапустить службу${blue}                                ║${plain}"
        echo -e "${blue}║${plain}  ${green}5${plain} 📊 Показать статус${blue}                                     ║${plain}"
        echo -e "${blue}║${plain}  ${green}6${plain} 🗑️  Удалить только службу${blue}                               ║${plain}"
        echo -e "${blue}║${plain}  ${green}7${plain} 💥 Полная очистка (служба + меню + файлы)${blue}               ║${plain}"
        echo -e "${blue}║${plain}  ${green}0${plain} 🔚 Выйти${blue}                                            ║${plain}"
        echo -e "${blue}╚═══════════════════════════════════════════════════════════════════╝${plain}"
        echo
        read -rp "Выберите пункт: " choice
        case "$choice" in
            1) install_forwarder   ;;
            2) start_service       ;;
            3) stop_service        ;;
            4) restart_service     ;;
            5) show_status         ;;
            6) remove_service_interactive ;;
            7) full_cleanup_interactive   ;;
            0) exit 0              ;;
            *) warn "Неверный выбор: $choice" ;;
        esac
        echo
        read -rp "Нажмите Enter чтобы продолжить..." _ || true
    done
}

# -------------------------
# CLI parsing
# -------------------------
show_help() {
    cat <<EOF
Использование:
  sudo bash install.sh         - Запустить инсталлятор/менеджер (скрипт сам установит копию в ${INSTALL_DIR})
  sudo /opt/amneziawg-forwarder/install.sh --menu  - Запустить меню (устанавливается как /usr/local/bin/menu)
  sudo /opt/amneziawg-forwarder/install.sh --install - Только установка форвардера и сервиса
  sudo /opt/amneziawg-forwarder/install.sh --remove-service - Только удалить службу
  sudo /opt/amneziawg-forwarder/install.sh --full-clean - Полная очистка (без удаления текущего файла)
  sudo /opt/amneziawg-forwarder/install.sh --status - Показать статус
  --help - показать это сообщение
EOF
}

main() {
    if [[ "${1:-}" == "--menu" ]]; then
        show_menu
        exit 0
    fi

    case "${1:-}" in
        --install) install_forwarder ;;
        --remove-service) remove_service_only ;;
        --full-clean) full_cleanup ;;
        --status) show_status ;;
        --help) show_help ;;
        "" ) # запуск без аргументов — интерактивно показываем меню
            show_menu
            ;;
        * )
            warn "Неизвестный параметр: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
