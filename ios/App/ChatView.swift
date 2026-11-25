// One conversation: the transcript, the approval cards, and the composer.
//
// The transcript is whatever the harness folded — settled text, tool chips,
// option cards, screenshots. This renders those and nothing else; it does
// not re-derive anything from provider events, because the server already
// did that and having two folds is how two clients start disagreeing.
import SwiftUI
import CompanionCore
// Unconditional, because the uses below are: `Color(uiColor:)` and
// `UIImage(data:)` are reached on every path through this file. A
// `canImport` guard around the import alone does not make the file portable
// — it only moves the failure from "no such module" to "no such type", and
// hides that this view is iOS-only behind something that looks like it
// isn't. The App target is iOS; CompanionCore is where the portable half
// lives.
import UIKit

struct ChatView: View {
    let chat: Chat
    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft = ""
    @State private var showingTasks = false
    @State private var shareFile: ShareFile?
    /// StaffMate 的对话页把聊天记录和输入区拆在 ZStack 的两层，
    /// 输入区高度通过 preference 回写给正文留白。这里沿用同一套结构。
    @State private var composerHeight: CGFloat = 62
    @State private var keyboardUp = false
    @StateObject private var headerScroll = NativeListScrollModel()
    @FocusState private var composerFocused: Bool

    /// The live bubble's scroll target. A constant because there is at most
    /// one per chat and it has no message id to borrow.
    static let liveBubbleId = "companion.live"

    private var messages: [Message] {
        session.state.visibleTranscript(forThread: chat.threadId)
    }

    /// The live chat record, so busy/unread stay current as frames land.
    private var current: Chat {
        switch chat {
        case let .bot(bot): return session.state.bot(bot.id).map(Chat.bot) ?? chat
        case let .room(room):
            return session.state.rooms.first { $0.id == room.id }.map(Chat.room) ?? chat
        }
    }

    var body: some View {
        // Read the transcript once for this render. Pagination changes the
        // array as a unit; repeatedly reaching through ObservableObject for
        // every row only recomputes the same value.
        let transcript = messages
        /* 页面结构逐项取自 StaffMate NativeChatDetailView：
           ZStack 负责背景、正文、页头和输入区四层；正文用
           safeAreaInset 给输入区留出实测高度，首条消息从页头下方 72pt
           开始，滚动后仍可穿到玻璃按钮下面。 */
        ZStack(alignment: .bottom) {
            background

            conversation(transcript)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: composerHeight + 8)
                }

            NativeObservedScrollHeaderFrost(model: headerScroll)
                .frame(maxHeight: .infinity, alignment: .top)
                .zIndex(1)

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
            }
            .zIndex(2)

            composer
                .padding(.bottom, keyboardUp ? 8 : windowBottomInset)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ChatComposerHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(.container, edges: .bottom)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .background(NativeSwipeBackEnabler().frame(width: 0, height: 0))
        .onPreferenceChange(ChatComposerHeightKey.self) { height in
            if height > 0, abs(height - composerHeight) > 0.5 {
                composerHeight = height
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.22)) { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.22)) { keyboardUp = false }
        }
        .task {
            // opening a chat is what marks it read, exactly as on the desktop
            if current.unread { await session.markRead(current) }
        }
        .onChange(of: current.unread) { _, unread in
            // A message can arrive while this chat is already on screen. The
            // initial task above will not run again, so clear that new unread
            // bit here rather than leaving a badge on an open conversation.
            if unread { Task { await session.markRead(current) } }
        }
        .sheet(isPresented: $showingTasks) {
            if case let .bot(bot) = current { TaskManagerView(bot: bot) }
        }
        .sheet(item: $shareFile) { file in
            ActivityShareSheet(items: [file.url])
        }
    }

    /// StaffMate NativeChatDetail.swift:2893.
    private var background: some View {
        ZStack {
            ChatDesign.page
            RadialGradient(
                colors: [
                    ChatDesign.accent.opacity(colorScheme == .dark ? 0.12 : 0.07),
                    .clear,
                ],
                center: .topLeading,
                startRadius: 8,
                endRadius: 340
            )
        }
        .ignoresSafeArea()
    }

    /// StaffMate NativeChatDetail.swift:2917，唯一变更是右侧拆成
    /// OpenMaus 的电脑入口和 StaffMate 的更多入口两颗独立玻璃圆钮。
    private var header: some View {
        ZStack {
            HStack(spacing: 7) {
                MausAvatar(color: current.color, size: 24)
                Text(current.name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 132, alignment: .leading)
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .frame(height: 36)
            .modifier(ChatHeaderIdentitySurface())

            HStack(spacing: 8) {
                Button {
                    dismiss()
                } label: {
                    ChatHeaderGlassButton(size: ChatHeaderMetrics.button) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.primary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")

                Spacer(minLength: 8)

                if case let .bot(bot) = current {
                    NavigationLink {
                        ComputerView(bot: bot)
                    } label: {
                        ChatHeaderGlassButton(size: ChatHeaderMetrics.button) {
                            Image(systemName: "display")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.primary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Watch \(bot.name)'s computer")
                }

                Menu {
                    if case let .bot(bot) = current {
                        Button("任务", systemImage: "square.stack") {
                            showingTasks = true
                        }
                        .disabled(bot.busy == true)
                    }
                    Button("分享为 Markdown", systemImage: "doc.plaintext") {
                        Task {
                            if let url = await session.export(
                                threadId: current.threadId,
                                format: "markdown"
                            ) {
                                shareFile = ShareFile(url: url)
                            }
                        }
                    }
                    Button("分享为 JSON", systemImage: "curlybraces") {
                        Task {
                            if let url = await session.export(
                                threadId: current.threadId,
                                format: "json"
                            ) {
                                shareFile = ShareFile(url: url)
                            }
                        }
                    }
                } label: {
                    ChatHeaderGlassButton(size: ChatHeaderMetrics.button) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.primary)
                    }
                }
                .tint(.primary)
                .accessibilityLabel("会话操作")
            }
        }
        .padding(.horizontal, ChatHeaderMetrics.inset)
        .frame(height: 56)
    }

    /// StaffMate NativeChatDetail.swift:3086.
    private func conversation(_ transcript: [Message]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    Color.clear
                        .frame(height: 1)
                        .background(
                            NativeListScrollObserver { value in
                                headerScroll.report(value)
                            }
                        )

                    if session.state.hasMore[chat.threadId] == true {
                        Button {
                            let anchor = transcript.first?.id
                            Task {
                                await session.loadOlder(threadId: chat.threadId)
                                if let anchor {
                                    proxy.scrollTo(anchor, anchor: .top)
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.up")
                                Text("查看更早的消息")
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 34)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(
                        Array(transcript.enumerated()),
                        id: \.element.id
                    ) { index, message in
                        VStack(alignment: .leading, spacing: 12) {
                            if startsANewStretch(at: index, in: transcript) {
                                Text(RelativeStamp.separator(message.date))
                                    .font(.system(size: 13))
                                    .foregroundStyle(Color.secondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 6)
                            }
                            MessageRow(chat: current, message: message)
                                .transition(.asymmetric(
                                    insertion: .offset(y: 16).combined(with: .opacity),
                                    removal: .opacity
                                ))
                        }
                        .id(message.id)
                    }

                    if let live = session.state.streaming[chat.threadId], !live.isEmpty {
                        StreamingBubble(text: live, reasoning: nil)
                            .id(Self.liveBubbleId)
                    } else if let thinking = session.state.reasoning[chat.threadId],
                              !thinking.isEmpty {
                        StreamingBubble(text: nil, reasoning: thinking)
                            .id(Self.liveBubbleId)
                    }

                    Color.clear.frame(height: 1).id("chat-bottom")
                }
                .padding(.horizontal, 14)
                .padding(.top, 72)
                .padding(.bottom, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: transcript.last?.id) { _, _ in
                guard transcript.last != nil else { return }
                withAnimation(.easeOut(duration: 0.20)) {
                    proxy.scrollTo("chat-bottom", anchor: .bottom)
                }
            }
            .onChange(of: session.state.streaming[chat.threadId]?.count ?? 0) { _, length in
                guard length > 0 else { return }
                proxy.scrollTo(Self.liveBubbleId, anchor: .bottom)
            }
            .onChange(of: session.focusedMessageId) { _, messageId in
                guard let messageId,
                      messages.contains(where: { $0.id == messageId })
                else { return }
                withAnimation { proxy.scrollTo(messageId, anchor: .center) }
                session.consumeFocus(messageId)
            }
            .task {
                guard let messageId = session.focusedMessageId,
                      messages.contains(where: { $0.id == messageId })
                else { return }
                proxy.scrollTo(messageId, anchor: .center)
                session.consumeFocus(messageId)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// OpenMaus 原有视觉：隔半小时以上的消息保留时间分段。
    private func startsANewStretch(at index: Int, in messages: [Message]) -> Bool {
        guard index > 0 else { return true }
        return messages[index].at - messages[index - 1].at > 30 * 60 * 1000
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await session.send(text, to: current) }
    }

    /// StaffMate ChatComposer.composerBar：43pt 高，半径 21.5pt。
    /// OpenMaus 没有附件和语音上传协议，因此不摆无法执行的圆钮。
    private var composer: some View {
        HStack(alignment: .bottom, spacing: 9) {
            HStack(alignment: .bottom, spacing: 2) {
                TextField(
                    "给 \(current.name) 发消息",
                    text: $draft,
                    axis: .vertical
                )
                .font(.system(size: 15.5))
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.leading, 14)
                .padding(.trailing, canSend || current.busy ? 2 : 0)
                .padding(.vertical, 10)
                .frame(minHeight: 43, alignment: .leading)
                .submitLabel(.send)
                .onKeyPress(.return, phases: .down) { press in
                    guard !press.modifiers.contains(.shift) else { return .ignored }
                    submit()
                    return .handled
                }
                .onSubmit(submit)

                if current.busy, case let .bot(bot) = current {
                    Button {
                        Task { await session.interrupt(bot: bot) }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ChatDesign.accentInk)
                            .frame(width: 33, height: 33)
                            .background(ChatDesign.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 43, height: 43)
                    .accessibilityLabel("停止任务")
                } else if canSend {
                    Button {
                        submit()
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(ChatDesign.accentInk)
                            .frame(width: 33, height: 33)
                            .background(ChatDesign.accent, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 43, height: 43)
                    .accessibilityLabel("发送")
                }
            }
            .chatGlassSurface(
                RoundedRectangle(cornerRadius: 21.5, style: .continuous)
            )
            .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: canSend)
        .animation(.spring(response: 0.26, dampingFraction: 0.82), value: current.busy)
    }

    private var windowBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
    }
}

struct MessageRow: View {
    let chat: Chat
    let message: Message
    @EnvironmentObject private var session: Session
    @State private var editingText = ""
    @State private var showingEdit = false

    private static let reactionChoices = ["👍", "❤️", "😂", "🎉", "👀"]

    private var versions: [Message] {
        session.state.versions(of: message, inThread: chat.threadId)
    }

    var body: some View {
        // StaffMate ChatMessageRow：用户侧留 44pt，员工侧留 30pt。
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user { Spacer(minLength: 44) }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                content

                if let comm = message.comm {
                    Label("Messaged \(comm.withName)", systemImage: "arrow.up.right.bubble")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.secondary)
                }

                if let reactions = message.reactions, !reactions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(reactionGroups(reactions), id: \.emoji) { group in
                            Button("\(group.emoji) \(group.count)") {
                                Task {
                                    await session.react(
                                        to: message,
                                        in: chat.threadId,
                                        emoji: group.emoji
                                    )
                                }
                            }
                            .font(.system(size: 13))
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .tint(group.mine ? ChatDesign.accent : Color.secondary)
                        }
                    }
                }

                if versions.count > 1,
                   let index = versions.firstIndex(where: { $0.id == message.id }),
                   case let .bot(bot) = chat {
                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await session.switchVersion(
                                    to: versions[index - 1],
                                    for: bot
                                )
                            }
                        } label: { Image(systemName: "chevron.left") }
                        .disabled(index == 0 || bot.busy == true)
                        Text("\(index + 1) of \(versions.count)")
                        Button {
                            Task {
                                await session.switchVersion(
                                    to: versions[index + 1],
                                    for: bot
                                )
                            }
                        } label: { Image(systemName: "chevron.right") }
                        .disabled(index + 1 >= versions.count || bot.busy == true)
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.secondary)
                }
            }

            if message.role != .user { Spacer(minLength: 30) }
        }
        .frame(
            maxWidth: .infinity,
            alignment: message.role == .user ? .trailing : .leading
        )
        .contextMenu {
            ForEach(Self.reactionChoices, id: \.self) { emoji in
                Button(emoji) { Task { await session.react(to: message, in: chat.threadId, emoji: emoji) } }
            }
            if message.role == .user, message.kind == .text, case let .bot(bot) = chat {
                Divider()
                Button("Edit and retry", systemImage: "pencil") {
                    editingText = message.text ?? ""
                    showingEdit = true
                }
                .disabled(bot.busy == true)
            }
        }
        .alert("Edit and retry", isPresented: $showingEdit) {
            TextField("Message", text: $editingText)
            Button("Cancel", role: .cancel) {}
            if case let .bot(bot) = chat {
                Button("Send") {
                    let text = editingText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    Task { await session.edit(message, for: bot, text: text) }
                }
            }
        } message: {
            Text("This creates a new version and continues from there.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .text:
            TextBubble(message: message)
        case .options:
            CardView(chat: chat, message: message)
        case .activity:
            ActivityChip(tool: message.tool)
        case .screen:
            ScreenShot(threadId: chat.threadId, message: message)
        case .unknown:
            // A message kind from a newer computer. Almost everything the
            // harness sends carries `text`, so showing it is usually the
            // whole message and always better than a gap in the transcript.
            // When there is nothing to show, show nothing — a placeholder
            // saying "unsupported" is a worse gap than the gap.
            if let text = message.text, !text.isEmpty {
                TextBubble(message: message)
            }
        }
    }

    private func reactionGroups(_ reactions: [Reaction]) -> [(emoji: String, count: Int, mine: Bool)] {
        Dictionary(grouping: reactions, by: \.emoji)
            .map { (emoji: $0.key, count: $0.value.count, mine: $0.value.contains { $0.by == "user" }) }
            .sorted { $0.emoji < $1.emoji }
    }
}

private struct ShareFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct TextBubble: View {
    let message: Message

    var body: some View {
        let mine = message.role == .user
        VStack(alignment: .leading, spacing: 4) {
            // rooms attribute each line to the member who said it
            if let from = message.from {
                Text(from.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MausPalette.color(from.color))
            }
            // Bots get markdown, you do not — the same split the desktop
            // makes. Markdown you did not intend is worse than markdown
            // you did: a message about `**` should show the asterisks.
            if mine {
                Text(message.text ?? "")
                    .font(.system(size: 17))
                    .foregroundStyle(ChatDesign.accentInk)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                MarkdownText(source: message.text ?? "")
                    .foregroundStyle(Color.primary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // StaffMate ChatMessageRow.bubble：13 × 9、17pt 圆角、0.5pt 描边。
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background {
            if mine {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(ChatDesign.accent)
            } else {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(
                    mine ? Color.white.opacity(0.16) : Color.primary.opacity(0.06),
                    lineWidth: 0.5
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

/// A tool the bot ran. Deliberately quiet — these are the bulk of a busy
/// transcript and they are context, not content.
struct ActivityChip: View {
    let tool: ToolActivity?

    var body: some View {
        if let tool {
            // StaffMate NCWorkProcessView.header 的单步版本。
            HStack(spacing: 3.9) {
                ZStack {
                    Circle()
                        .fill(
                            tool.ok == false
                                ? Color.red.opacity(0.14)
                                : Color.primary.opacity(0.06)
                        )
                    Image(
                        systemName: tool.ok == false
                            ? "exclamationmark"
                            : "sparkles"
                    )
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(
                        tool.ok == false
                            ? Color.red.opacity(0.82)
                            : Color.primary.opacity(0.55)
                    )
                }
                .frame(width: 14, height: 14)
                .padding(.trailing, 2.6)

                Text(tool.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(
                        tool.ok == false
                            ? Color.red.opacity(0.80)
                            : Color.primary.opacity(0.60)
                    )

                Spacer(minLength: 0)
            }
            .frame(maxWidth: 326, minHeight: 28, alignment: .leading)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
    }
}

/// An option card. When it still has a request behind it, this is the
/// screen the companion exists for — a bot stopped, and only a person can
/// let it continue.
struct CardView: View {
    let chat: Chat
    let message: Message
    @EnvironmentObject private var session: Session
    @State private var answering = false

    /// The option this card offers that means "go ahead".
    ///
    /// Deliberately not the literal string "Allow". `options` is whatever the
    /// harness sent, and it only falls back to ["Allow", "Deny"] when the
    /// provider event named no choices of its own (`server/index.ts`) — a card
    /// is free to say "Yes", "Approve", "Allow once". Answering with a string
    /// the card never offered writes the grant and then hands the harness a
    /// choice it can reject, so the bot stays stopped with nothing on screen
    /// to explain it. The conventional label wins when it is present, which
    /// keeps the ordinary permission card behaving exactly as before.
    private var allowChoice: String? {
        guard let options = message.card?.options else { return nil }
        return options.first { $0.caseInsensitiveCompare("Allow") == .orderedSame }
            ?? options.first { !Self.isRefusal($0) }
    }

    /// One definition of "the refusal", shared by the button tint and the
    /// choice above so the two cannot drift apart.
    private static func isRefusal(_ option: String) -> Bool {
        option.caseInsensitiveCompare("Deny") == .orderedSame
    }

    var body: some View {
        if let card = message.card {
            // StaffMate AskCardView 的外层尺寸、材质和选项行参数。
            VStack(alignment: .leading, spacing: 10) {
                Text(card.title)
                    .font(.system(size: 14.5, weight: .semibold))
                Text(card.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                if let held = card.held {
                    Label(held, systemImage: "exclamationmark.shield")
                        .font(.system(size: 13))
                        .foregroundStyle(.orange)
                }

                if card.isPending {
                    VStack(spacing: 6) {
                        ForEach(card.options, id: \.self) { option in
                            Button {
                                answering = true
                                Task {
                                    await session.answer(threadId: chat.threadId, card: card, choice: option)
                                    answering = false
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Text(option)
                                        .font(.system(size: 13.5))
                                        .foregroundStyle(
                                            Self.isRefusal(option) ? Color.secondary : Color.primary
                                        )
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(
                                    Color.primary.opacity(0.05),
                                    in: RoundedRectangle(
                                        cornerRadius: 10,
                                        style: .continuous
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(answering)
                        }
                    }

                    // The grant key comes from the card. The phone never
                    // derives its own, so it cannot permit something subtly
                    // wider than the computer would have. The same goes for
                    // the answer: it is one of the options the card offered,
                    // never a string invented here.
                    if card.allowKey != nil, let allow = allowChoice, case let .bot(bot) = chat {
                        Button("Always allow this tool") {
                            answering = true
                            Task {
                                await session.alwaysAllow(bot: bot, card: card)
                                await session.answer(threadId: chat.threadId, card: card, choice: allow)
                                answering = false
                            }
                        }
                        .font(.system(size: 13.5))
                        .disabled(answering)
                    }
                } else if let answered = card.answered {
                    Label(answered, systemImage: "checkmark.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                }
            }
            .padding(13)
            .frame(maxWidth: 320, alignment: .leading)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(ChatDesign.accent.opacity(0.22), lineWidth: 0.8)
            }
        }
    }
}

/// A frame of the bot's computer. In the paged shape the pixels are not in
/// the transcript — they are fetched here, once, when the row appears.
struct ScreenShot: View {
    let threadId: String
    let message: Message
    @EnvironmentObject private var session: Session
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(height: 160)
                    .overlay {
                        ProgressView()
                            .tint(ChatDesign.accent)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    }
            }
        }
        .task {
            guard image == nil else { return }
            let data: Data?
            if let inline = message.png, let decoded = Data(base64Encoded: inline) {
                data = decoded
            } else if message.hasImage == true {
                data = await session.image(threadId: threadId, messageId: message.id)
            } else {
                data = nil
            }
            image = data.flatMap(UIImage.init(data:))
        }
    }
}

/// The reply as it is being typed, styled to match the settled bubble it is
/// about to become — the handover should be invisible, and any difference in
/// padding or corner radius reads as the message jumping on arrival.
///
/// A caret rather than a spinner: a spinner says "something is happening
/// somewhere", which the reader already knows. A caret at the end of real
/// text says how far along it is.
///
/// The caret does not blink, deliberately. The obvious way to blink it —
/// `withAnimation(.repeatForever) { flag.toggle() }` in `onAppear` — animates
/// the change once and then sits still, and a caret that blinks twice and
/// stops looks more broken than one that never blinks. A correct version
/// animates opacity on a separate view, which needs a device to get right;
/// static is honest until then.
struct StreamingBubble: View {
    let text: String?
    let reasoning: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                if let reasoning, !reasoning.isEmpty, text?.isEmpty != false {
                    // Quieter and smaller than an answer, because it is not
                    // one. Tail-limited: reasoning runs to thousands of words
                    // and the part worth seeing is always the end.
                    //
                    // Plain text, unlike the answer: the tail cut lands
                    // wherever it lands, and rendering markdown that starts
                    // mid-syntax invents structure the model did not write.
                    Text(String(reasoning.suffix(400)))
                        .font(.system(size: 14))
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let text, !text.isEmpty {
                    // Same renderer as the settled bubble, for the same
                    // reason as the padding: a live reply showing `**bold**`
                    // that snaps to bold on arrival is the message jumping,
                    // just in a different dimension. The parser tolerates the
                    // half-finished markdown this is always holding — an
                    // unclosed fence renders as code, an unclosed link as the
                    // characters typed so far.
                    MarkdownText(source: text, caret: true)
                        .foregroundStyle(Color.primary)
                }
            }
            // 与 ChatMessageRow.bubble 完全一致，避免流式结束时气泡跳动。
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            }
            Spacer(minLength: 30)
        }
        // No `.textSelection` on purpose: selecting text that is still growing
        // fights the reader, and the settled bubble a frame later is
        // selectable anyway.
    }
}

// MARK: - StaffMate shared visual primitives

/// StaffMate NativePages.swift:962.
private enum ChatDesign {
    static var page: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor.systemGroupedBackground
                : UIColor(red: 0.945, green: 0.945, blue: 0.963, alpha: 1)
        })
    }

    /// OpenMaus has no user-selectable StaffMate accent palette. Its native
    /// accent is the project-wide system accent already used by the rest of
    /// the iOS screens.
    static var accent: Color { Color.accentColor }
    static var accentInk: Color { Color.white }
}

/// StaffMate NativePages.swift:375.
private enum ChatHeaderMetrics {
    static let inset: CGFloat = 16
    static let button: CGFloat = 40
    static let navigationHeight: CGFloat = 44
    static let headerFrostOverscan: CGFloat = 4

    static var safeAreaTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.top ?? 47
    }

    static var systemHeaderOverlap: CGFloat {
        safeAreaTop + navigationHeight
    }
}

/// StaffMate NativePages.swift:326, copied without changing its hierarchy.
private struct ChatGlassSurface<S: Shape>: ViewModifier {
    let shape: S

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
                .overlay(
                    shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(
                    shape.stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}

private extension View {
    func chatGlassSurface<S: Shape>(_ shape: S) -> some View {
        modifier(ChatGlassSurface(shape: shape))
    }
}

/// StaffMate NativePages.swift:355.
private struct ChatHeaderGlassButton<Content: View>: View {
    var size: CGFloat = 40
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: size, height: size)
            .chatGlassSurface(Circle())
            .contentShape(Circle())
    }
}

/// StaffMate NativeChatDetail.swift:2452.
private struct ChatHeaderIdentitySurface: ViewModifier {
    func body(content: Content) -> some View {
        content.chatGlassSurface(Capsule(style: .continuous))
    }
}

/// StaffMate NativeChatDetail.swift:12.
private struct ChatComposerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// StaffMate NativePages.swift:1018. Hiding the system navigation bar also
/// disables the system's edge swipe unless it is explicitly reinstated.
private struct NativeSwipeBackEnabler: UIViewControllerRepresentable {
    final class Probe: UIViewController, UIGestureRecognizerDelegate {
        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            enable()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enable()
        }

        private func enable() {
            guard let navigationController else { return }
            navigationController.interactivePopGestureRecognizer?.isEnabled = true
            navigationController.interactivePopGestureRecognizer?.delegate = self
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }

    func makeUIViewController(context: Context) -> Probe {
        Probe()
    }

    func updateUIViewController(_ controller: Probe, context: Context) {}
}

/// StaffMate NativePages.swift:408.
@MainActor
private final class NativeListScrollModel: ObservableObject {
    @Published private(set) var headerProgress: CGFloat = 0

    func report(_ scrolled: CGFloat) {
        let next = min(1, max(0, (scrolled - 2) / 42))
        if abs(next - headerProgress) > 0.005 {
            headerProgress = next
        }
    }
}

/// StaffMate NativePages.swift:454. The chat list only needs the observer's
/// scroll channel; the source file's group-picker snapping is not part of a
/// conversation and is therefore not carried over.
private struct NativeListScrollObserver: UIViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeUIView(context: Context) -> Probe {
        Probe(onScroll: onScroll)
    }

    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.onScroll = onScroll
    }

    final class Probe: UIView {
        var onScroll: (CGFloat) -> Void
        private var offsetObservation: NSKeyValueObservation?
        private weak var scrollView: UIScrollView?

        init(onScroll: @escaping (CGFloat) -> Void) {
            self.onScroll = onScroll
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { nil }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else {
                offsetObservation = nil
                scrollView = nil
                return
            }
            DispatchQueue.main.async { [weak self] in self?.attach() }
        }

        private func attach() {
            guard offsetObservation == nil else { return }
            var view = superview
            while let current = view {
                if let scroll = current as? UIScrollView {
                    scrollView = scroll
                    offsetObservation = scroll.observe(
                        \.contentOffset,
                        options: [.new, .initial]
                    ) { [weak self, weak scroll] _, _ in
                        guard let self, let scroll else { return }
                        let value = max(
                            0,
                            scroll.contentOffset.y + scroll.adjustedContentInset.top
                        )
                        if Thread.isMainThread {
                            self.onScroll(value)
                        } else {
                            DispatchQueue.main.async { [weak self] in
                                self?.onScroll(value)
                            }
                        }
                    }
                    return
                }
                view = current.superview
            }
        }
    }
}

/// StaffMate NativePages.swift:621.
private struct NativeScrollHeaderFrost: View {
    let progress: CGFloat

    private var amount: CGFloat {
        min(1, max(0, progress))
    }

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .frame(
                height: ChatHeaderMetrics.systemHeaderOverlap
                    + ChatHeaderMetrics.headerFrostOverscan
            )
            .frame(maxWidth: .infinity, alignment: .top)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.95), location: 0),
                        .init(color: .black.opacity(0.68), location: 0.58),
                        .init(color: .black.opacity(0.45), location: 0.86),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(amount)
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// StaffMate NativePages.swift:661.
private struct NativeObservedScrollHeaderFrost: View {
    @ObservedObject var model: NativeListScrollModel

    var body: some View {
        NativeScrollHeaderFrost(progress: model.headerProgress)
    }
}
