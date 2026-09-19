import Foundation
import AppKit

final class AppState: ObservableObject {
    @Published var server: String { didSet { if !loading { saveSettings() } } }
    @Published var localPort: String { didSet { if !loading { saveSettings() } } }
    @Published var sshPort: String { didSet { if !loading { saveSettings() } } }
    @Published var autoRestart: Bool {
        didSet {
            if loading { return }
            saveSettings()
            log.log(autoRestart ? "Автовосстановление включено" : "Автовосстановление выключено")
            updateMonitor()
        }
    }

    let log = LogStore()
    private let store = SettingsStore()
    private var loading = true
    private var lastSaved: Settings?
    private var monitorTimer: Timer?
    private var monitorBusy = false
    private var actionBusy = false

    var settings: Settings {
        Settings(
            server: server,
            localPort: Int(localPort) ?? 1080,
            sshPort: Int(sshPort) ?? 22,
            autoRestart: autoRestart
        )
    }

    init() {
        let result = store.load()
        let s: Settings
        switch result {
        case .loaded(let loaded):
            s = loaded
        case .createdDefault(let created):
            s = created
        case .corruptedDefault(let reset):
            s = reset
        }
        server = s.server
        localPort = String(s.localPort)
        sshPort = String(s.sshPort)
        autoRestart = s.autoRestart
        loading = false
        lastSaved = s

        log.log("Программа запущена")
        switch result {
        case .loaded:
            log.log("Конфиг загружен: \(s.server), порт \(s.localPort), ssh-порт \(s.sshPort)")
        case .createdDefault:
            log.log("Конфиг не найден, создан с настройками по умолчанию")
        case .corruptedDefault:
            log.log("Конфиг повреждён, сброшен на настройки по умолчанию")
        }
        if s.autoRestart {
            log.log("Проверка туннеля при запуске")
            TunnelManager.check(localPort: s.localPort) { [weak self] ok, _ in
                guard let self else { return }
                self.log.log(ok ? "OK: tunnel is working" : "FAIL: tunnel is down")
                if ok {
                    self.log.log("Автовосстановление включено, мониторинг запущен")
                    self.updateMonitor()
                } else {
                    self.log.log("Туннель не работает, мониторинг не запущен")
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.shutdown()
        }
    }

    private func saveSettings() {
        let s = settings
        guard s != lastSaved else { return }
        lastSaved = s
        do {
            try store.save(s)
            log.log("Конфиг сохранён")
        } catch {
            log.log("ОШИБКА: не удалось сохранить конфиг: \(error.localizedDescription)")
        }
    }

    func startTapped() {
        guard !actionBusy else {
            log.log("Старт уже выполняется, повторное нажатие проигнорировано")
            return
        }
        actionBusy = true
        let s = settings
        log.log("Старт: проверка туннеля")
        TunnelManager.check(localPort: s.localPort) { [weak self] ok, _ in
            guard let self else { return }
            if ok {
                self.log.log("Туннель уже работает")
                self.actionBusy = false
                return
            }
            self.log.log("Туннель не работает, запуск: ssh -D \(s.localPort) -p \(s.sshPort) \(s.server)")
            TunnelManager.start(settings: s) { ok, output in
                if !ok {
                    self.log.log("ОШИБКА: запуск туннеля не удался\(output.isEmpty ? "" : ": \(output)")")
                    self.actionBusy = false
                    return
                }
                self.log.log("Команда запуска выполнена, проверка туннеля")
                TunnelManager.check(localPort: s.localPort) { working, _ in
                    self.log.log(working ? "OK: tunnel is working" : "FAIL: tunnel is down")
                    if working && self.autoRestart && self.monitorTimer == nil {
                        self.log.log("Автовосстановление включено, мониторинг запущен")
                        self.updateMonitor()
                    }
                    self.actionBusy = false
                }
            }
        }
    }

    func checkTapped() {
        log.log("Проверка туннеля")
        TunnelManager.check(localPort: settings.localPort) { [weak self] ok, _ in
            self?.log.log(ok ? "OK: tunnel is working" : "FAIL: tunnel is down")
        }
    }

    func stopTapped() {
        guard !actionBusy else {
            log.log("Другое действие ещё выполняется, Стоп проигнорирован")
            return
        }
        actionBusy = true
        let port = settings.localPort
        log.log("Стоп: проверка туннеля")
        TunnelManager.check(localPort: port) { [weak self] ok, _ in
            guard let self else { return }
            if !ok && !TunnelManager.isTunnelProcessRunning(localPort: port) {
                self.log.log("Туннель не запущен")
                self.actionBusy = false
                return
            }
            self.log.log("Остановка туннеля: pkill -f \"ssh -D \(port)\"")
            TunnelManager.stop(localPort: port) {
                self.log.log("Туннель остановлен")
                self.stopMonitor()
                self.actionBusy = false
            }
        }
    }

    func chromeTapped() {
        guard !actionBusy else {
            log.log("Другое действие ещё выполняется, запуск Chrome проигнорирован")
            return
        }
        actionBusy = true
        if TunnelManager.isChromeRunning() {
            log.log("Chrome уже запущен, запрос подтверждения")
            let alert = NSAlert()
            alert.messageText = "Chrome уже запущен"
            alert.informativeText = "Закрыть текущий Chrome и запустить заново через туннель?"
            alert.addButton(withTitle: "Да")
            alert.addButton(withTitle: "Нет")
            guard alert.runModal() == .alertFirstButtonReturn else {
                log.log("Запуск Chrome отменён пользователем")
                actionBusy = false
                return
            }
            log.log("Закрытие Chrome")
            TunnelManager.quitChrome { [weak self] in
                self?.launchChrome()
            }
        } else {
            launchChrome()
        }
    }

    func telegramTapped() {
        guard !actionBusy else {
            log.log("Другое действие ещё выполняется, запуск Telegram проигнорирован")
            return
        }
        actionBusy = true
        let bundleId = "com.tdesktop.Telegram"
        if TunnelManager.isAppRunning(bundleId: bundleId) {
            log.log("Telegram уже запущен, запрос подтверждения")
            let alert = NSAlert()
            alert.messageText = "Telegram уже запущен"
            alert.informativeText = "Закрыть текущий Telegram и запустить заново?"
            alert.addButton(withTitle: "Да")
            alert.addButton(withTitle: "Нет")
            guard alert.runModal() == .alertFirstButtonReturn else {
                log.log("Запуск Telegram отменён пользователем")
                actionBusy = false
                return
            }
            log.log("Закрытие Telegram")
            TunnelManager.quitApp(processName: "Telegram", bundleId: bundleId) { [weak self] in
                self?.launchTelegram()
            }
        } else {
            launchTelegram()
        }
    }

    private func launchTelegram() {
        let s = settings
        log.log("Проверка туннеля перед запуском Telegram")
        TunnelManager.check(localPort: s.localPort) { [weak self] ok, _ in
            guard let self else { return }
            if ok {
                self.log.log("Запуск Telegram")
                TunnelManager.openTelegram()
                self.actionBusy = false
                return
            }
            self.log.log("Туннель не работает, запуск: ssh -D \(s.localPort) -p \(s.sshPort) \(s.server)")
            TunnelManager.start(settings: s) { started, output in
                if started {
                    self.log.log("Туннель запущен")
                    self.log.log("Запуск Telegram")
                    TunnelManager.openTelegram()
                } else {
                    self.log.log("ОШИБКА: запуск туннеля не удался\(output.isEmpty ? "" : ": \(output)"), Telegram не запущен")
                }
                self.actionBusy = false
            }
        }
    }

    private func launchChrome() {
        let s = settings
        log.log("Проверка туннеля перед запуском Chrome")
        TunnelManager.check(localPort: s.localPort) { [weak self] ok, _ in
            guard let self else { return }
            if ok {
                self.log.log("Запуск Chrome через socks5://127.0.0.1:\(s.localPort)")
                TunnelManager.openChrome(localPort: s.localPort)
                self.actionBusy = false
                return
            }
            self.log.log("Туннель не работает, запуск: ssh -D \(s.localPort) -p \(s.sshPort) \(s.server)")
            TunnelManager.start(settings: s) { started, output in
                if started {
                    self.log.log("Туннель запущен")
                    self.log.log("Запуск Chrome через socks5://127.0.0.1:\(s.localPort)")
                    TunnelManager.openChrome(localPort: s.localPort)
                } else {
                    self.log.log("ОШИБКА: запуск туннеля не удался\(output.isEmpty ? "" : ": \(output)"), Chrome не запущен")
                }
                self.actionBusy = false
            }
        }
    }

    private func stopMonitor() {
        guard monitorTimer != nil else { return }
        monitorTimer?.invalidate()
        monitorTimer = nil
        monitorBusy = false
        log.log("Мониторинг остановлен")
    }

    private func updateMonitor() {
        monitorTimer?.invalidate()
        monitorTimer = nil
        guard autoRestart else { return }
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.monitorTick()
        }
    }

    private func monitorTick() {
        guard !monitorBusy else { return }
        monitorBusy = true
        let s = settings
        TunnelManager.check(localPort: s.localPort) { [weak self] ok, _ in
            guard let self else { return }
            if ok {
                self.monitorBusy = false
                return
            }
            self.log.log("Автовосстановление: обрыв туннеля, перезапуск")
            TunnelManager.stop(localPort: s.localPort) {
                TunnelManager.start(settings: s) { started, output in
                    guard self.autoRestart, self.monitorTimer != nil else {
                        TunnelManager.stop(localPort: s.localPort) {
                            self.monitorBusy = false
                        }
                        return
                    }
                    guard started else {
                        self.log.log("ОШИБКА: автовосстановление: запуск не удался\(output.isEmpty ? "" : ": \(output)")")
                        self.failMonitor()
                        return
                    }
                    TunnelManager.check(localPort: s.localPort) { ok2, _ in
                        guard self.monitorTimer != nil else {
                            TunnelManager.stop(localPort: s.localPort) {
                                self.monitorBusy = false
                            }
                            return
                        }
                        if ok2 {
                            self.log.log("Автовосстановление: туннель восстановлен")
                            self.monitorBusy = false
                        } else {
                            self.log.log("ОШИБКА: автовосстановление: туннель не работает после перезапуска")
                            self.failMonitor()
                        }
                    }
                }
            }
        }
    }

    private func failMonitor() {
        log.log("Автовосстановление остановлено")
        monitorBusy = false
        autoRestart = false
    }

    func shutdown() {
        monitorTimer?.invalidate()
        let port = settings.localPort
        if TunnelManager.isTunnelProcessRunning(localPort: port) {
            TunnelManager.stopSync(localPort: port)
        }
    }
}
