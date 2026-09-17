import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model = AppModel()

    var body: some View {
        ZStack {
            BackgroundView()
            VStack(spacing: 14) {
                HeaderView()
                SourcePanel(model: model)
                    .layoutPriority(1)
                Connector(ready: model.canCopy || model.phase == .success)
                DestinationPanel(model: model)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                BottomBar(model: model)
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 28)
        }
        .frame(width: 520, height: 740, alignment: .top)
        .alert("拷贝失败", isPresented: $model.showError) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "未知错误")
        }
        .background(WindowBackdrop())
    }
}

private struct BackgroundView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.appBgTop, .appBgBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color.appAccent.opacity(0.16), .clear],
                center: .top,
                startRadius: 10,
                endRadius: 360
            )
            .offset(y: -80)
        }
        .ignoresSafeArea()
    }
}

private struct HeaderView: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.appAccent.opacity(0.14))
                    .frame(width: 52, height: 52)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.appAccent.opacity(0.28), lineWidth: 1)
                    .frame(width: 52, height: 52)
                Image(systemName: "externaldrive.badge.checkmark")
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
            }
            Text("拷到 exFAT")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("拷贝完成后自动同步缓存，降低磁盘损坏风险")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.48))
        }
    }
}

private struct SourcePanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("源文件", systemImage: "folder.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .labelStyle(.titleAndIcon)
                Spacer()
                if !model.sources.isEmpty {
                    Text("\(model.sources.count) 项 · \(Format.bytes(model.totalBytes))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                    Button("清空") { model.clearSources() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.appAccent.opacity(model.isBusy ? 0.3 : 0.9))
                        .disabled(model.isBusy)
                }
            }

            if model.sources.isEmpty {
                DropPlaceholder(
                    targeted: model.isSourceTargeted,
                    symbol: "arrow.down.doc",
                    title: "拖放文件或文件夹到此处",
                    subtitle: "支持同时选择多个文件"
                )
            } else {
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(model.sources) { item in
                                SourceRow(
                                    item: item,
                                    size: model.itemSizes[item.id],
                                    disabled: model.isBusy,
                                    onRemove: { model.remove(item) }
                                )
                            }
                        }
                        .padding(10)
                    }
                    .frame(height: 120)
                }
                .background(Color.appCard)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            model.isSourceTargeted ? Color.appAccent.opacity(0.7) : Color.appStroke,
                            lineWidth: model.isSourceTargeted ? 1.4 : 1
                        )
                }
            }

            HStack(spacing: 8) {
                GhostButton(title: "选择文件", symbol: "doc") {
                    model.pickFiles()
                }
                .disabled(model.isBusy)
                GhostButton(title: "选择文件夹", symbol: "folder") {
                    model.pickFolder()
                }
                .disabled(model.isBusy)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $model.isSourceTargeted) { providers in
            model.handleDrop(providers, toDestination: false)
        }
    }
}

private struct SourceRow: View {
    let item: SourceItem
    let size: Int64?
    let disabled: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .font(.system(size: 14))
                .foregroundStyle(item.isDirectory ? Color.appAccent : .white.opacity(0.55))
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text(size.map(Format.bytes) ?? "计算中…")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.38))
            }
            Spacer(minLength: 8)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.28))
            }
            .buttonStyle(.plain)
            .disabled(disabled)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct DestinationPanel: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("目标位置", systemImage: "externaldrive")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            if let dest = model.destination {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: dest.isExFAT ? "externaldrive.fill" : "externaldrive")
                            .font(.system(size: 22))
                            .foregroundStyle(dest.isExFAT ? Color.appAccent : Color.appWarning)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(dest.name)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                FormatBadge(format: dest.format, isExFAT: dest.isExFAT)
                            }
                            Text(dest.url.path)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.38))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        if dest.isEjectable {
                            Button {
                                model.ejectDestination()
                            } label: {
                                Image(systemName: "eject.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white.opacity(model.isBusy || model.isEjecting ? 0.25 : 0.72))
                                    .frame(width: 28, height: 28)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(model.isBusy || model.isEjecting)
                            .help("弹出磁盘")
                        }
                    }
                    CapacityBar(free: dest.freeBytes, total: dest.totalBytes)
                    if dest.isReadOnly {
                        Hint(text: "目标磁盘为只读，无法写入", tone: .danger)
                    } else if model.insufficientSpace {
                        Hint(text: "可用空间不足，还差 \(Format.bytes(model.totalBytes - dest.freeBytes))", tone: .danger)
                    } else if !dest.isExFAT {
                        Hint(text: "当前不是 exFAT，拷贝后仍会执行 sync", tone: .warning)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appCard)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            model.isDestTargeted ? Color.appAccent.opacity(0.7) : Color.appStroke,
                            lineWidth: model.isDestTargeted ? 1.4 : 1
                        )
                }
            } else {
                DropPlaceholder(
                    targeted: model.isDestTargeted,
                    symbol: "externaldrive.badge.plus",
                    title: "选择 exFAT 磁盘上的文件夹",
                    subtitle: "也可以把磁盘或文件夹拖到这里"
                )
            }

            HStack(spacing: 8) {
                GhostButton(title: model.destination == nil ? "选择目标文件夹" : "更改目标位置", symbol: "folder") {
                    model.pickDestination()
                }
                .disabled(model.isBusy || model.isEjecting)
                if model.destination?.isEjectable == true {
                    GhostButton(title: model.isEjecting ? "正在弹出…" : "弹出磁盘", symbol: "eject.fill") {
                        model.ejectDestination()
                    }
                    .disabled(model.isBusy || model.isEjecting)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $model.isDestTargeted) { providers in
            model.handleDrop(providers, toDestination: true)
        }
    }
}

private struct FormatBadge: View {
    let format: String
    let isExFAT: Bool

    var body: some View {
        Text(format)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(isExFAT ? Color.appAccent : Color.appWarning)
            .background((isExFAT ? Color.appAccent : Color.appWarning).opacity(0.14))
            .clipShape(Capsule())
    }
}

private struct CapacityBar: View {
    let free: Int64
    let total: Int64

    var usedFraction: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(Double(total - free) / Double(total))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(Color.appAccent.opacity(0.85))
                        .frame(width: max(4, geo.size.width * usedFraction))
                }
            }
            .frame(height: 5)
            Text("可用 \(Format.bytes(free)) / 共 \(Format.bytes(total))")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}

private struct Connector: View {
    let ready: Bool

    var body: some View {
        HStack {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 30, height: 30)
                Circle()
                    .strokeBorder(ready ? Color.appAccent.opacity(0.5) : Color.appStroke, lineWidth: 1)
                    .frame(width: 30, height: 30)
                Image(systemName: "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ready ? Color.appAccent : .white.opacity(0.35))
            }
            Spacer()
        }
        .padding(.vertical, -2)
    }
}

private struct BottomBar: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            switch model.phase {
            case .idle:
                PrimaryButton(
                    title: "拷贝并同步",
                    symbol: "arrow.down.circle.fill",
                    enabled: model.canCopy
                ) {
                    model.startCopy()
                }
            case .copying, .syncing:
                ProgressCard(model: model)
            case .success:
                SuccessCard(model: model)
            }
        }
    }
}

private struct ProgressCard: View {
    @Bindable var model: AppModel
    var syncing: Bool { model.phase == .syncing }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(syncing ? "正在同步磁盘缓存…" : "正在拷贝")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                if !syncing {
                    Button("取消") { model.cancelCopy() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            ProgressView(value: syncing ? 1 : model.progress.fraction)
                .progressViewStyle(.linear)
                .tint(Color.appAccent)
                .animation(.linear(duration: 0.08), value: model.progress.bytesDone)
            HStack {
                Text(syncing ? "写入完成后可安全弹出磁盘" : model.progress.currentName)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                Spacer()
                if !syncing {
                    Text("\(Format.bytes(model.progress.bytesDone)) / \(Format.bytes(model.progress.bytesTotal))")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
        .padding(14)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.appAccent.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct SuccessCard: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appSuccess)
                    .font(.system(size: 20))
                VStack(alignment: .leading, spacing: 2) {
                    Text("拷贝完成")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("已同步磁盘缓存，可以安全弹出")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
            }
            HStack(spacing: 8) {
                GhostButton(title: "继续拷贝", symbol: "plus") {
                    model.resetAfterSuccess()
                }
                if model.destination?.isEjectable == true {
                    PrimaryButton(
                        title: model.isEjecting ? "正在弹出…" : "弹出磁盘",
                        symbol: "eject.fill",
                        enabled: !model.isEjecting,
                        compact: true
                    ) {
                        model.ejectDestination()
                    }
                } else {
                    GhostButton(title: "在 Finder 中显示", symbol: "folder") {
                        model.revealDestination()
                    }
                }
            }
        }
        .padding(14)
        .background(Color.appSuccess.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.appSuccess.opacity(0.28), lineWidth: 1)
        }
    }
}

private struct DropPlaceholder: View {
    let targeted: Bool
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(targeted ? Color.appAccent : .white.opacity(0.35))
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(targeted ? 0.92 : 0.7))
            Text(subtitle)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.35))
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .background(targeted ? Color.appAccent.opacity(0.08) : Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    targeted ? Color.appAccent.opacity(0.7) : Color.white.opacity(0.12),
                    style: StrokeStyle(lineWidth: targeted ? 1.4 : 1, dash: targeted ? [] : [5, 4])
                )
        }
        .animation(.easeInOut(duration: 0.18), value: targeted)
    }
}

private struct GhostButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(.white.opacity(0.82))
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.appStroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct PrimaryButton: View {
    let title: String
    let symbol: String
    var enabled: Bool = true
    var compact: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                Text(title)
                    .font(.system(size: compact ? 12.5 : 14.5, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, compact ? 9 : 12)
            .foregroundStyle(enabled ? Color.black.opacity(0.84) : .white.opacity(0.42))
            .background(enabled ? Color.appAccent : Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.85)
    }
}

private struct Hint: View {
    enum Tone { case warning, danger }
    let text: String
    let tone: Tone

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: tone == .danger ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11.5))
        }
        .foregroundStyle(tone == .danger ? Color.appDanger : Color.appWarning)
    }
}

private struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isOpaque = true
            window.backgroundColor = NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.11, alpha: 1)
            window.styleMask.insert(.fullSizeContentView)
            window.hasShadow = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

#Preview {
    ContentView()
}
