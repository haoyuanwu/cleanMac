import SwiftUI

struct ChoiceItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var symbol: String = ""
    var subtitle: String? = nil
    var id: Value { value }
}

/// 自绘选项列表：一次点击直接看到分类，无嵌套系统菜单。
struct ChoiceDropdown<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [ChoiceItem<Value>]
    var symbol = "arrow.up.arrow.down"
    @State private var showing = false
    @FocusState private var focused: Value?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var current: ChoiceItem<Value>? { options.first { $0.value == selection } }
    var body: some View {
        Button { showing.toggle() } label: {
            HStack(spacing: 7) {
                Image(systemName: current.flatMap { $0.symbol.isEmpty ? nil : $0.symbol } ?? symbol)
                Text(current?.title ?? title).lineLimit(1).truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(showing ? 180 : 0))
            }
        }
        .buttonStyle(ReadableControlButtonStyle(selected: showing))
        .accessibilityLabel(title).accessibilityValue(current?.title ?? "未选择")
        .animation(reduceMotion ? nil : Theme.ease, value: showing)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(options) { option in
                        Button {
                            withAnimation(reduceMotion ? nil : Theme.ease) { selection = option.value }
                            showing = false
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: option.symbol.isEmpty ? symbol : option.symbol).frame(width: 18)
                                Text(option.title).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "checkmark").opacity(selection == option.value ? 1 : 0)
                            }.padding(.horizontal, 10).frame(minHeight: 36)
                                .foregroundStyle(Theme.actionInk)
                                .background(selection == option.value || focused == option.value ? Theme.controlWash : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8))
                                .contentShape(RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(WorkspacePressStyle()).focused($focused, equals: option.value)
                            .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                    }
                }.padding(8)
            }.frame(width: 230, height: min(320, CGFloat(options.count) * 40 + 16))
                .background(Theme.surfaceRaised)
                .onAppear { focused = selection }
                .onExitCommand { showing = false }
                .onMoveCommand { direction in
                    guard let index = options.firstIndex(where: { $0.value == (focused ?? selection) }), !options.isEmpty else { return }
                    if direction == .down { focused = options[(index + 1) % options.count].value }
                    if direction == .up { focused = options[(index + options.count - 1) % options.count].value }
                }
        }
    }
}

/// 共享自绘分段轨道及滑动高亮，不依赖 NSSegmentedControl。
struct ChoiceSegments<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [ChoiceItem<Value>]
    @Namespace private var highlight
    @FocusState private var focused: Value?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                Button {
                    withAnimation(reduceMotion ? nil : Theme.springSnappy) { selection = option.value }
                } label: {
                    VStack(spacing: 3) {
                        HStack(spacing: 5) {
                            if !option.symbol.isEmpty { Image(systemName: option.symbol) }
                            Text(option.title)
                        }.font(.system(size: 12, weight: .semibold))
                        if let subtitle = option.subtitle { Text(subtitle).font(.system(size: 10)) }
                    }.foregroundStyle(selection == option.value ? Color.white : Theme.actionInk)
                        .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: option.subtitle == nil ? 30 : 48)
                        .background {
                            if selection == option.value {
                                RoundedRectangle(cornerRadius: 8).fill(Theme.actionAccent)
                                    .matchedGeometryEffect(id: "selected", in: highlight)
                            }
                        }.contentShape(RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(WorkspacePressStyle()).focused($focused, equals: option.value)
                    .accessibilityLabel(option.title + (option.subtitle.map { "，" + $0 } ?? ""))
                    .accessibilityAddTraits(selection == option.value ? .isSelected : [])
            }
        }.padding(3).background(Theme.controlWash, in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Theme.actionInk.opacity(0.3)))
            .accessibilityElement(children: .contain).accessibilityLabel(title)
            .onMoveCommand { direction in
                guard !options.isEmpty, let index = options.firstIndex(where: { $0.value == (focused ?? selection) }) else { return }
                let delta = direction == .right ? 1 : direction == .left ? -1 : 0
                guard delta != 0 else { return }
                let next = options[(index + options.count + delta) % options.count].value
                withAnimation(reduceMotion ? nil : Theme.springSnappy) { selection = next; focused = next }
            }
    }
}
