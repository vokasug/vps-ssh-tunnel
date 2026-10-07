import SwiftUI

struct ContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var log: LogStore

    init(state: AppState) {
        _state = ObservedObject(wrappedValue: state)
        _log = ObservedObject(wrappedValue: state.log)
    }

    private enum Field { case server, localPort, sshPort }
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 16) {
            header

            HStack(alignment: .top, spacing: 16) {
                connectionCard
                servicesCard
                    .frame(width: 280)
            }
            .fixedSize(horizontal: false, vertical: true)

            logCard
        }
        .padding(16)
        .frame(minWidth: 740, minHeight: 560)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.08), Color.accentColor.opacity(0.02), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .onAppear {
            DispatchQueue.main.async {
                focusedField = nil
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11)
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .blue.opacity(0.35), radius: 6, y: 3)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("VPS SSH Tunnel")
                    .font(.title2.weight(.bold))
                Text(state.server)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            tunnelStatusPill
        }
    }

    private var tunnelStatusPill: some View {
        let (text, color): (String, Color) = {
            switch state.tunnelUp {
            case .some(true): return ("Туннель работает", .green)
            case .some(false): return ("Туннель не работает", .red)
            case .none: return ("Статус неизвестен", .gray)
            }
        }()
        return HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.8), radius: 3)
            Text(text)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().stroke(.quaternary))
    }

    private var connectionCard: some View {
        card {
            sectionHeader(icon: "network", title: "Подключение")

            HStack(spacing: 10) {
                labeledField(title: "Сервер (user@host или алиас)", prompt: "root@1.1.1.1",
                             text: $state.server, field: .server)
                labeledField(title: "Локальный порт", prompt: "1080",
                             text: $state.localPort, field: .localPort)
                    .frame(width: 110)
                labeledField(title: "SSH порт", prompt: "22",
                             text: $state.sshPort, field: .sshPort)
                    .frame(width: 80)
            }

            HStack(spacing: 10) {
                Button { state.startTapped() } label: {
                    HStack(spacing: 6) {
                        Label("Старт", systemImage: "play.fill")
                        Text("⌘T").opacity(0.7)
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("t", modifiers: .command)

                Button { state.checkTapped() } label: {
                    Label("Проверка", systemImage: "checkmark.circle")
                }
                .buttonStyle(.bordered)

                Button { state.stopTapped() } label: {
                    Label("Стоп", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .disabled(state.actionBusy)

            Toggle("Восстанавливать туннель при обрыве", isOn: $state.autoRestart)
                .toggleStyle(.switch)
        }
    }

    private var servicesCard: some View {
        card {
            sectionHeader(icon: "bolt.fill", title: "Сервисы")

            serviceButton(
                title: "Chrome",
                hint: "⌘B",
                icon: { AnyView(Image(systemName: "globe").foregroundStyle(.tint)) },
                action: { state.chromeTapped() }
            )
            .keyboardShortcut("b", modifiers: .command)
            .disabled(state.actionBusy)

            serviceButton(
                title: "Telegram",
                hint: "⌘G",
                icon: { AnyView(Image(systemName: "paperplane.fill").foregroundStyle(.tint)) },
                action: { state.telegramTapped() }
            )
            .keyboardShortcut("g", modifiers: .command)
            .disabled(state.actionBusy)

            serviceButton(
                title: "Opencode Telegram",
                hint: "⌘O",
                active: state.otRunning,
                busy: state.otBusy,
                icon: {
                    AnyView(
                        Circle()
                            .fill(state.otRunning ? Color.green : Color.gray.opacity(0.45))
                            .frame(width: 10, height: 10)
                            .shadow(color: state.otRunning ? .green.opacity(0.9) : .clear, radius: 4)
                    )
                },
                action: { state.opencodeTelegramTapped() }
            )
            .keyboardShortcut("o", modifiers: .command)
        }
    }

    private var logCard: some View {
        card {
            HStack {
                sectionHeader(icon: "terminal.fill", title: "Журнал")
                Spacer()
                Button { log.copyAll() } label: {
                    Label("Копировать", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Text(log.text.isEmpty ? " " : log.text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                .onChange(of: log.text) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .frame(minHeight: 160)
        }
    }

    private func serviceButton(title: String, hint: String,
                               hintColor: Color = .secondary,
                               active: Bool = false,
                               busy: Bool = false,
                               icon: () -> AnyView,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon()
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                if busy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(hint)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(hintColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(active ? Color.green.opacity(0.14) : Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(active ? Color.green.opacity(0.55) : Color.primary.opacity(0.1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
            Text(title)
                .font(.headline)
        }
    }

    private func labeledField(title: String, prompt: String,
                              text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(focusedField == field ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12))
                )
                .focused($focusedField, equals: field)
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.quaternary)
        )
        .shadow(color: .black.opacity(0.07), radius: 8, y: 3)
    }
}
