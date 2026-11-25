// The roster.
//
// Styled after the desktop's messaging-app feel rather than a settings
// list: big mascot faces, the bot's role as a chip beside its name, a
// preview line, and no dividers. Anything waiting on you is pulled to the
// top, because that is the one thing a phone is better at than the laptop.
import SwiftUI
import CompanionCore

struct ChatListView: View {
    @EnvironmentObject private var session: Session
    @State private var query = ""
    /// Driven so that making a bot can open it. Value-based navigation alone
    /// cannot push without a tap, and a new bot appearing silently at the
    /// bottom of the roster is a poor answer to pressing +.
    @State private var path = NavigationPath()
    @State private var searchHits: [SearchHit] = []
    @State private var searching = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            // Identity and creation stay at the top; search and the menu sit
            // just above the thumb as separate floating controls. A hand-built
            // header avoids the extra room an empty navigation bar reserves.
            VStack(spacing: 0) {
                header
                StatusBanner()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        if query.isEmpty {
                            ForEach(session.state.pendingApprovals, id: \.message.id) { pending in
                                if let chat = chat(forThread: pending.threadId) {
                                    NavigationLink(value: chat) {
                                        WaitingRow(chat: chat, card: pending.message.card)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !query.isEmpty, !searchHits.isEmpty {
                            HStack {
                                Text("消息")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.secondary)
                                Spacer()
                                if searching { ProgressView().controlSize(.small) }
                            }
                            .padding(.top, 10)
                            .padding(.bottom, 4)

                            ForEach(searchHits) { hit in
                                Button {
                                    Task {
                                        if let chat = await session.open(hit) { path.append(chat) }
                                    }
                                } label: {
                                    SearchHitRow(hit: hit)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        ForEach(chats) { summary in
                            NavigationLink(value: summary.chat) {
                                ChatRow(
                                    chat: summary.chat,
                                    preview: summary.preview,
                                    at: summary.lastActivity
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    // Leave the last row clear of the floating controls.
                    .padding(.bottom, 88)
                }
                .refreshable { await session.refresh() }
                .scrollDismissesKeyboard(.interactively)
                .overlay {
                    if chats.isEmpty && searchHits.isEmpty {
                        ContentUnavailableView(
                            query.isEmpty ? "还没有机器人" : "没有匹配结果",
                            systemImage: query.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass",
                            description: Text(
                                query.isEmpty
                                    ? "你在电脑上创建的机器人会显示在这里。"
                                    : "没有与“\(query)”匹配的对话。"
                            )
                        )
                    }
                }
            }
            .overlay(alignment: .bottom) { bottomTools }
            // top-aligned: the roster fills downward from the header
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Chat.self) { ChatView(chat: $0) }
            .task(id: query) {
                let expected = query
                guard expected.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 else {
                    searchHits = []
                    searching = false
                    return
                }
                searching = true
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, query == expected else { return }
                searchHits = await session.search(expected)
                searching = false
            }
        }
    }

    /// Who you are on the left, and how to add a bot on the right.
    private var header: some View {
        HStack {
            ProfileAvatar(name: session.connection?.name ?? "You")
                .accessibilityLabel("你的账户")

            Spacer(minLength: 12)

            Button {
                Task {
                    if let bot = await session.createBot() { path.append(Chat.bot(bot)) }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .floatingGlass(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("新建机器人")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .frame(height: 60)
    }

    private var bottomTools: some View {
        HStack(spacing: 10) {
            NavigationLink {
                ConnectedAppsView()
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 44, height: 44)
                    .floatingGlass(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .accessibilityLabel("连接应用")

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.secondary)

                TextField("搜索对话", text: $query)
                    .font(.system(size: 16))
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($searchFocused)

                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .floatingGlass(Capsule(), interactive: true)

            if isSearchActive {
                Button {
                    cancelSearch()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .accessibilityLabel("取消搜索")
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.22), value: isSearchActive)
    }

    private var isSearchActive: Bool {
        searchFocused || !query.isEmpty
    }

    private func cancelSearch() {
        searchFocused = false
        query = ""
        searchHits = []
        searching = false
    }

    private var chats: [ChatSummary] {
        let all = session.state.chatSummaries
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.chat.name.localizedCaseInsensitiveContains(query)
                || $0.chat.subtitle.localizedCaseInsensitiveContains(query)
                || $0.preview.localizedCaseInsensitiveContains(query)
        }
    }

    private func chat(forThread threadId: String) -> Chat? {
        if let bot = session.state.bot(forThread: threadId) { return .bot(bot) }
        if let room = session.state.room(forThread: threadId) { return .room(room) }
        return nil
    }
}

/// A circle that uses the system's glass material on iOS 26, with the
/// equivalent native material on older releases.
private extension View {
    @ViewBuilder
    func floatingGlass<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay {
                    shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
    }
}

struct SearchHitRow: View {
    let hit: SearchHit

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hit.role == .user ? "person.fill" : "bubble.left.fill")
                .foregroundStyle(Color.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.secondary.opacity(0.13)))

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(hit.name).font(.system(size: 15, weight: .semibold))
                    if let task = hit.task, !task.isEmpty {
                        Text(task).font(.system(size: 12)).foregroundStyle(Color.secondary)
                    }
                    Spacer()
                    Text(RelativeStamp.list(hit.at))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }
                Text(hit.snippet)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

struct ChatRow: View {
    let chat: Chat
    let preview: String
    let at: Double

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            MausAvatar(color: chat.color, size: 52)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(chat.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .layoutPriority(1)

                    // the bot's job, the way the desktop shows it
                    if !chat.subtitle.isEmpty {
                        Text(chat.subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.secondary)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }

                    Spacer(minLength: 4)

                    Text(RelativeStamp.list(at))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                        .fixedSize()
                }

                HStack(alignment: .top, spacing: 8) {
                    Text(preview.isEmpty ? " " : preview)
                        .font(.system(size: 15))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if chat.busy {
                        ProgressView().controlSize(.mini)
                    } else if chat.unread {
                        Circle()
                            .fill(MausPalette.color(chat.color))
                            .frame(width: 9, height: 9)
                            .padding(.top, 5)
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

/// A bot that stopped and needs a person. The whole reason for the app, so
/// it gets to sit above the roster and look unlike everything else.
struct WaitingRow: View {
    let chat: Chat
    let card: OptionCard?

    var body: some View {
        HStack(spacing: 12) {
            MausAvatar(color: chat.color, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Label("\(chat.name) 正在等你处理", systemImage: "hand.raised.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Text(card?.subtitle ?? "")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
        )
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Connection state, shown only when it is not "fine".
struct StatusBanner: View {
    @EnvironmentObject private var session: Session

    var body: some View {
        Group {
            switch session.status {
            case .live, .unpaired:
                EmptyView()
            case .connecting:
                banner("正在连接…", systemImage: "arrow.triangle.2.circlepath", tint: .secondary)
            case let .offline(reason):
                banner(reason, systemImage: "wifi.slash", tint: .orange)
            case .unauthorized:
                banner("电脑端已解除此手机的配对。", systemImage: "lock.slash", tint: .red)
            }
        }
        .animation(.default, value: session.status)
    }

    private func banner(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .padding(.top, 4)
    }
}

/// Timestamps the way a messaging app writes them.
enum RelativeStamp {
    /// Roster: time today, weekday this week, date beyond that.
    static func list(_ at: Double) -> String {
        guard at > 0 else { return "" }
        let date = Date(timeIntervalSince1970: at / 1000)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "昨天" }
        if let week = calendar.date(byAdding: .day, value: -6, to: Date()), date > week {
            return date.formatted(.dateTime.weekday(.wide))
        }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }

    /// In a transcript: enough to place a gap in the conversation.
    static func separator(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "今天 \(time)" }
        if calendar.isDateInYesterday(date) { return "昨天 \(time)" }
        return "\(date.formatted(.dateTime.day().month(.abbreviated))) \(time)"
    }
}
