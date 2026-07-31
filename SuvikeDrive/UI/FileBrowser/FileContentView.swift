//
//  FileContentView.swift
//  SuvikeDrive
//  Target: SuvikeDriveUI
//  Module: FileBrowser 文件浏览器
//  功能：原生 macOS NSTableView 列表，支持表头悬浮、完美 Finder 风格、列宽拖拽
//  Author: Andything
//  Date: 2026-07-29
//

import SwiftUI
import AppKit

// MARK: - SwiftUI 桥接层
struct FileContentView: NSViewRepresentable, Equatable {
    let files: [FileInfo]
    let viewModel: FileBrowserViewModel
    let onFileSelected: ((FileInfo?) -> Void)?
    
    // ✅ 核心防闪步骤：告诉 SwiftUI 什么时候“不需要重绘”
    static func == (lhs: FileContentView, rhs: FileContentView) -> Bool {
        // 1. 如果文件数量不一样，必须重绘
        guard lhs.files.count == rhs.files.count else { return false }
        
        // 2. 如果数量一样，我们通过数组最后 ID 的对比来决定是否重绘
        // 这样能避免后台频率极低的同步导致整个界面大闪烁
        if let lastLhs = lhs.files.last, let lastRhs = rhs.files.last {
            return lastLhs.id == lastRhs.id
        }
        // 3. 如果数组是空的，也不重绘
        return lhs.files.isEmpty && rhs.files.isEmpty
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor
        
        let tableView = NSTableView()
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.rowHeight = 24
        tableView.selectionHighlightStyle = .regular
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.tableViewDoubleClicked(_:))
        
        // 配置列
        let nameCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        nameCol.title = "名称"
        nameCol.width = 250
        nameCol.minWidth = 120
        
        let sizeCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Size"))
        sizeCol.title = "大小"
        sizeCol.width = 100
        sizeCol.minWidth = 70
        
        let dateCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Date"))
        dateCol.title = "修改日期"
        dateCol.width = 160
        dateCol.minWidth = 120
        
        let statusCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Status"))
        statusCol.title = "状态"
        statusCol.width = 100
        statusCol.minWidth = 80
        
        tableView.addTableColumn(nameCol)
        tableView.addTableColumn(sizeCol)
        tableView.addTableColumn(dateCol)
        tableView.addTableColumn(statusCol)
        
        scrollView.documentView = tableView
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView else { return }
        
        // 获取旧数据（上一帧的数据）
        let oldFiles = context.coordinator.parent.files
        // 获取新数据（传入的参数）
        let newFiles = self.files
        
        // 1. 更新持有的数据，必须放在比较逻辑后面，否则无法区分新旧。
        context.coordinator.parent = self
        
        // 2. 如果文件数量变了（增删文件），必须暴力全量刷新
        if oldFiles.count != newFiles.count {
            tableView.reloadData()
            return
        }
        
        // 3. ✅ 核心优化：如果数量没变，通过 id 对比，只更新“变了”的那几行
        var rowsToReload = IndexSet()
        for index in 0..<newFiles.count {
            // 检查是否文件本身发生了变化（名字、大小、时间、路径变了）
            let isDifferent = oldFiles[index].id != newFiles[index].id ||
                              oldFiles[index].path != newFiles[index].path ||
                              oldFiles[index].size != newFiles[index].size ||
                              oldFiles[index].modificationDate != newFiles[index].modificationDate
            
            if isDifferent {
                rowsToReload.insert(index)
            }
        }
        
        // 4. ✅ 如果有变动的行，只刷新这几行，其他行保持原样，没有任何闪动！
        if !rowsToReload.isEmpty {
            let allColumns = IndexSet(integersIn: 0..<tableView.numberOfColumns)
            tableView.reloadData(forRowIndexes: rowsToReload, columnIndexes: allColumns)
        }
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: FileContentView
        
        init(_ parent: FileContentView) {
            self.parent = parent
        }
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            return parent.files.count
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.files.count else { return nil }
            let file = parent.files[row]
            let columnID = tableColumn?.identifier.rawValue ?? ""
            
            let cell = NSTableCellView()
            let textField = NSTextField(labelWithString: "")
            textField.font = .systemFont(ofSize: 13)
            textField.isEditable = false
            textField.isSelectable = false
            textField.drawsBackground = false
            textField.lineBreakMode = .byTruncatingTail
            textField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(textField)
            cell.textField = textField
            
            // 名称列（带图标，独立布局）
            if columnID == "Name" {
                let icon = NSImageView()
                icon.translatesAutoresizingMaskIntoConstraints = false
                icon.image = NSImage(systemSymbolName: file.isDirectory ? "folder" : "doc", accessibilityDescription: nil)
                icon.contentTintColor = file.isDirectory ? .controlAccentColor : .secondaryLabelColor
                cell.addSubview(icon)
                textField.stringValue = file.name
                
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor, constant: 1.5),
                    icon.widthAnchor.constraint(equalToConstant: 16),
                    icon.heightAnchor.constraint(equalToConstant: 16),
                    textField.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4)
                ])
            } else {
                // 其他列：大小、日期、状态 (✅ 对齐到标题左侧边缘)
                NSLayoutConstraint.activate([
                    textField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 0),
                    textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
                ])
            }
            
            // 填充具体内容
            if columnID == "Name" {
                // 已填充
            } else if columnID == "Size" {
                textField.stringValue = file.isDirectory ? "--" : formatFileSize(file.size)
                textField.alignment = .left
            } else if columnID == "Date" {
                textField.stringValue = formatFileDate(file.modificationDate)
            } else if columnID == "Status" {
                let state = parent.viewModel.getSyncState(for: file)
                textField.stringValue = state.tooltip
                textField.textColor = NSColor(state.color)
            }
            
            return cell
        }
        
        @objc func tableViewDoubleClicked(_ sender: Any?) {
            let tableView = sender as? NSTableView
            let row = tableView?.clickedRow ?? -1
            if row >= 0, row < parent.files.count {
                let item = parent.files[row]
                parent.onFileSelected?(item)
                if item.isDirectory {
                    parent.viewModel.openItem(item)
                }
            }
        }
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            if row >= 0, row < parent.files.count {
                parent.onFileSelected?(parent.files[row])
            } else {
                parent.onFileSelected?(nil)
            }
        }
    }
}
