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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Сервер (user@host или алиас)").font(.caption).foregroundStyle(.secondary)
                    TextField("root@1.1.1.1", text: $state.server)
                        .focused($focusedField, equals: .server)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Локальный порт").font(.caption).foregroundStyle(.secondary)
                    TextField("1080", text: $state.localPort)
                        .frame(width: 70)
                        .focused($focusedField, equals: .localPort)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("SSH порт").font(.caption).foregroundStyle(.secondary)
                    TextField("22", text: $state.sshPort)
                        .frame(width: 60)
                        .focused($focusedField, equals: .sshPort)
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    focusedField = nil
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
            }

            HStack(spacing: 12) {
                Button(action: { state.startTapped() }) {
                    HStack(spacing: 4) {
                        Text("Старт")
                        Text("⌘T").foregroundStyle(.secondary)
                    }
                }
                .keyboardShortcut("t", modifiers: .command)
                Button("Проверка") { state.checkTapped() }
                Button("Стоп") { state.stopTapped() }
                Button(action: { state.telegramTapped() }) {
                    HStack(spacing: 4) {
                        Text("Telegram")
                        Text("⌘G").foregroundStyle(.secondary)
                    }
                }
                .keyboardShortcut("g", modifiers: .command)
                Button(action: { state.chromeTapped() }) {
                    HStack(spacing: 4) {
                        Text("Chrome")
                        Text("⌘B").foregroundStyle(.secondary)
                    }
                }
                .keyboardShortcut("b", modifiers: .command)
                Spacer()
                Toggle("Восстанавливать при обрыве", isOn: $state.autoRestart)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Text(log.text.isEmpty ? " " : log.text)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
                .onChange(of: log.text) { _ in
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }

            HStack {
                Spacer()
                Button("Копировать весь лог") { log.copyAll() }
            }
        }
        .padding()
        .frame(minWidth: 640, minHeight: 440)
    }
}
