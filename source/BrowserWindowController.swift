import Cocoa

class BrowserWindowController:NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSWindowDelegate {
	let browserDelegate = RootBrowserDelegate()
	let outlineView = CopyOutlineView()
	let window:NSWindow = {
		let contentRect = NSMakeRect(0.0, 0.0, 300, 200)
		let styleMask:NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
		let window = NSWindow(contentRect:contentRect, styleMask:styleMask, backing:.buffered, defer:true)
		window.minSize = NSMakeSize(300.0, 200.0)
		window.isReleasedWhenClosed = false
		window.tabbingMode = .disallowed
		return window
	}()
	
	func open(_ title:String) {
		browserDelegate.start()
		
		window.center()
		window.setFrameAutosaveName(NSWindow.FrameAutosaveName("Browser Window"))
		window.title = title
		window.delegate = self
		
		let scrollView = NSScrollView()
		scrollView.autohidesScrollers = true
		scrollView.borderType = .noBorder
		scrollView.hasHorizontalScroller = true
		scrollView.hasVerticalScroller = true
		scrollView.translatesAutoresizingMaskIntoConstraints = false
		
		let contentView:NSView = window.contentView!
		contentView.wantsLayer = true // Fix for AppKit issue where outline view draws the bottom window corners
		contentView.addSubview(scrollView)
		
		NSLayoutConstraint.activate([
			scrollView.topAnchor.constraint(equalTo:contentView.topAnchor),
			scrollView.bottomAnchor.constraint(equalTo:contentView.bottomAnchor),
			scrollView.leadingAnchor.constraint(equalTo:contentView.leadingAnchor),
			scrollView.trailingAnchor.constraint(equalTo:contentView.trailingAnchor)
			])
		
		outlineView.allowsColumnReordering = false
		outlineView.allowsColumnResizing = false
		outlineView.allowsColumnSelection = false
		outlineView.allowsEmptySelection = true
		outlineView.allowsMultipleSelection = true
		outlineView.allowsTypeSelect = true
		outlineView.autoresizesOutlineColumn = false
		outlineView.headerView = nil
		outlineView.setDraggingSourceOperationMask([.copy], forLocal:false) // Allow drags to other apps
		outlineView.usesAlternatingRowBackgroundColors = false
		
		let column = NSTableColumn()
		column.isEditable = false
		column.resizingMask = .autoresizingMask
		outlineView.addTableColumn(column)
		outlineView.outlineTableColumn = column
		
		scrollView.documentView = outlineView
		
		outlineView.dataSource = self // Do this last, because it causes data source methods to be called
		
		NotificationCenter.default.addObserver(forName:.nodeDidAdd, object:nil, queue:nil, using:{
			let object = $0.object
			let parent = self.outlineView.parent(forItem:object)
			self.outlineView.reloadItem(parent, reloadChildren:true)
			self.outlineView.expandItem(object, expandChildren:true) // Auto-expand new items
		})
		NotificationCenter.default.addObserver(forName:.nodeDidRemove, object:nil, queue:nil, using:{
			let object = $0.object
			self.outlineView.reloadItem(object, reloadChildren:true)
		})
		NotificationCenter.default.addObserver(forName:.nodeDidUpdate, object:nil, queue:nil, using:{
			let object = $0.object
			self.outlineView.reloadItem(object, reloadChildren:true)
		})
		
		window.makeKeyAndOrderFront(self)
	}
	
	func windowWillClose(_ notification:Notification) {
		NotificationCenter.default.removeObserver(self, name:nil, object:nil)
		outlineView.dataSource = nil
		browserDelegate.stop()
	}
	
	func outlineView(_ outlineView:NSOutlineView, isItemExpandable item:Any) -> Bool {
		if item is BonjourNode {
			return true
		}
		return false
	}

	func outlineView(_ outlineView:NSOutlineView, numberOfChildrenOfItem item:Any?) -> Int {
		if item == nil {
			return browserDelegate.children.count
		}
		if let node = item as? BonjourNode {
			return node.children.count
		}
		return 0
	}
	
	func outlineView(_ outlineView:NSOutlineView, child index:Int, ofItem item:Any?) -> Any {
		if item == nil {
			return browserDelegate.children[index]
		}
		if let node = item as? BonjourNode {
			return node.children[index]
		}
		fatalError()
	}
	
	func outlineView(_ outlineView:NSOutlineView, objectValueFor tableColumn:NSTableColumn?, byItem item:Any?) -> Any? {
		if tableColumn == nil {
			return nil
		}
		if item == nil {
			return nil
		}
		if let node = item as? BonjourNode {
			return node.objectValue
		}
		return item
	}
	
	func outlineView(_ outlineView:NSOutlineView, pasteboardWriterForItem item:Any) -> NSPasteboardWriting? {
		if let node = item as? BonjourNode {
			return node.objectValue as NSString
		}
		else if let leaf = item as? NSString {
			return leaf
		}
		return nil
	}
}
