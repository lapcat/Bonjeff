import Cocoa

// Allows the Copy menu item to work
class CopyOutlineView:NSOutlineView {
	@objc func copy(_ sender:Any?) {
		var items = [NSPasteboardWriting]()
		for index in selectedRowIndexes {
			if let item = item(atRow:index) {
				if let writer = dataSource?.outlineView?(self, pasteboardWriterForItem:item) {
					items.append(writer)
				}
			}
		}
		
		let pasteboard = NSPasteboard.general
		pasteboard.clearContents()
		pasteboard.writeObjects(items)
	}
	
	@objc func validateMenuItem(_ menuItem:NSMenuItem) -> Bool {
		if let action:Selector = menuItem.action {
			if action == #selector(copy(_:)) {
				return numberOfSelectedRows > 0
			}
		}
		return true
	}
}
