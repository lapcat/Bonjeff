import Cocoa

class BrowserWindowController:NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSWindowDelegate {
	private static let expandedUserDefaultsKey = "ExpandedItems"
	private static let lowercasedExpandedUserDefaultsKey = "LowercasedExpandedItems"
	private let browserDelegate = RootBrowserDelegate()
	private let outlineView = CopyOutlineView()
	private let window:NSWindow = {
		let contentRect = NSMakeRect(0.0, 0.0, 300, 200)
		let styleMask:NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
		let window = NSWindow(contentRect:contentRect, styleMask:styleMask, backing:.buffered, defer:true)
		window.minSize = NSMakeSize(300.0, 200.0)
		window.isReleasedWhenClosed = false
		window.tabbingMode = .disallowed
		return window
	}()
	
	func open(_ title:String) {
		migrateUserDefaultsIfNecessary()
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
		
		outlineView.delegate = self
		outlineView.dataSource = self // Do this last, because it causes data source methods to be called
		
		NotificationCenter.default.addObserver(forName:.nodeDidAdd, object:nil, queue:nil, using:{
			let object = $0.object
			let parent = self.outlineView.parent(forItem:object)
			self.outlineView.reloadItem(parent, reloadChildren:true)
			if let node = object as? BonjourNode {
				if let expandedDefaults = UserDefaults.standard.dictionary(forKey:BrowserWindowController.expandedUserDefaultsKey) {
					let persistentName = node.persistentName
					if let expandedNumber = expandedDefaults[persistentName] as? NSNumber {
						if expandedNumber.boolValue {
							self.outlineView.expandItem(node)
						}
						return
					}
				}
				
				if node is DomainBrowserDelegate {
					// Expand new domains
					self.outlineView.expandItem(node)
				}
			}
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
	
	func outlineViewItemWillExpand(_ notification:Notification) {
		guard let userInfo = notification.userInfo else {
			return
		}
		guard let object = userInfo["NSObject"] else {
			return
		}
		guard let node = object as? BonjourNode else {
			return
		}
		
		if node is ServiceDelegate {
			node.start()
		}
		
		saveNode(node, expanded:true)
	}
	
	func outlineViewItemWillCollapse(_ notification:Notification) {
		guard let userInfo = notification.userInfo else {
			return
		}
		guard let object = userInfo["NSObject"] else {
			return
		}
		guard let node = object as? BonjourNode else {
			return
		}
		
		if node is ServiceDelegate {
			node.stop()
		}
		
		saveNode(node, expanded:false)
	}
	
	private func saveNode(_ node:BonjourNode, expanded:Bool) {
		let standardUserDefaults = UserDefaults.standard
		let key = BrowserWindowController.expandedUserDefaultsKey
		let persistentName = node.persistentName
		if var expandedDefaults = standardUserDefaults.dictionary(forKey:key) {
			if let expandedNumber = expandedDefaults[persistentName] as? NSNumber {
				if expandedNumber.boolValue == expanded {
					return // No change in value
				}
			}
			expandedDefaults[persistentName] = expanded
			standardUserDefaults.set(expandedDefaults, forKey:key)
		}
		else {
			standardUserDefaults.set([persistentName:expanded], forKey:key)
		}
	}
	
	private func migrateUserDefaultsIfNecessary() {
		// UserDefaults keys are lowercased starting in Bonjeff 1.0.2
		// Migrate Bonjeff 1.0.0 and 1.0.1 keys if necessary
		let standardUserDefaults = UserDefaults.standard
		let lowercaseExpandedKey = BrowserWindowController.lowercasedExpandedUserDefaultsKey
		let lowercasedExpanded = standardUserDefaults.bool(forKey:lowercaseExpandedKey)
		if !lowercasedExpanded {
			standardUserDefaults.set(true, forKey:lowercaseExpandedKey)
			
			let expandedKey = BrowserWindowController.expandedUserDefaultsKey
			if let expandedDefaults = standardUserDefaults.dictionary(forKey:expandedKey) {
				var newDefaults = [String:Any]()
				for (key, value) in expandedDefaults {
					newDefaults[key.lowercased()] = value
				}
				standardUserDefaults.set(newDefaults, forKey:expandedKey)
			}
		}
	}
}
