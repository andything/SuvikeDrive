//
//  SettingsComponents.swift
//  SuvikeDrive
//
//  功能: 偏好设置通用UI组件
//

import SwiftUI
import AppKit
import Combine

// MARK: - View Extension for Cursor
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - 胶囊标签视图
struct CapsuleTabView: View {
    let tabs: [String]
    @Binding var selection: Int
    @Namespace private var namespace
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs.indices, id: \.self) { index in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selection = index
                    }
                }) {
                    Text(tabs[index])
                        .font(.system(size: 13, weight: selection == index ? .semibold : .regular))
                        .foregroundColor(selection == index ? .white : .secondary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(
                            ZStack {
                                if selection == index {
                                    Capsule()
                                        .fill(Color.accentColor)
                                        .matchedGeometryEffect(id: "capsule", in: namespace)
                                } else {
                                    Capsule()
                                        .fill(Color.clear)
                                }
                            }
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.secondary.opacity(0.08))
        .clipShape(Capsule())
    }
}

// MARK: - 胶囊完成按钮
struct SettingsCapsuleDoneButton: View {
    let action: () -> Void
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text("完成")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(isHovering ? Color.accentColor.opacity(0.8) : Color.accentColor)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - 胶囊操作按钮
struct SettingsCapsuleActionButton: View {
    let title: String
    let action: () -> Void
    var backgroundColor: Color = Color.gray.opacity(0.15)
    var foregroundColor: Color = .primary
    @State private var isHovering: Bool = false
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(foregroundColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isHovering ? backgroundColor.opacity(1.2) : backgroundColor)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - ✅ Toggle 组件（通用开关）
struct ToggleView: View {
    let label: String
    @Binding var isOn: Bool
    var onChange: ((Bool) -> Void)?
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .padding(.leading, 4)
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .padding(.trailing, 4)
                .onChange(of: isOn) { _, newValue in
                    onChange?(newValue)
                }
        }
    }
}

// MARK: - ✅ GroupBox 标签视图
struct LabelView: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)
        }
    }
}

// MARK: - ✅ 通用 Menu 选择器组件
struct SettingsMenuPicker<ValueType>: View where ValueType: Hashable {
    let label: String
    @Binding var selection: ValueType
    let options: [ValueType]
    let formatter: (ValueType) -> String
    let width: CGFloat
    var disabled: Bool = false
    
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .padding(.leading, 4)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { option in
                    Button(formatter(option)) {
                        selection = option
                    }
                }
            } label: {
                Text(formatter(selection))
                    .font(.system(size: 12))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .frame(width: width, alignment: .trailing)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.1))
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(disabled)
            .opacity(disabled ? 0.5 : 1)
            .padding(.trailing, 4)
        }
    }
}
