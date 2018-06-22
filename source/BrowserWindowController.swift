import Cocoa

class BrowserWindowController:NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate, NSWindowDelegate {
	private static let expandedUserDefaultsKey = "ExpandedItems"
	private static let lowercasedExpandedUserDefaultsKey = "LowercasedExpandedItems"
	private let browserDelegate = RootBrowserDelegate()
	private let outlineView = CopyOutlineView()
	private let fontSize = NSFont.smallSystemFontSize
	private lazy var font = NSFont.systemFont(ofSize:fontSize)
	private let paragraphStyle:NSParagraphStyle = {
		let mutableStyle = NSMutableParagraphStyle()
		mutableStyle.alignment = .natural
		mutableStyle.lineBreakMode = .byTruncatingTail
		return mutableStyle.copy() as! NSParagraphStyle
	}()
	private lazy var fontAttributes:[NSAttributedStringKey:Any] = [.font:font,
																   .foregroundColor:NSColor.textColor,
																   .paragraphStyle:paragraphStyle]
	private lazy var boldFontAttributes:[NSAttributedStringKey:Any] = [.font:NSFont.boldSystemFont(ofSize:fontSize), 
																	   .foregroundColor:NSColor.textColor,
																	   .paragraphStyle:paragraphStyle]
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
		if let cell = column.dataCell as? NSCell {
			cell.font = font
			cell.lineBreakMode = .byTruncatingTail
			cell.truncatesLastVisibleLine = true
			cell.wraps = false
		}
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
				if let expandedDefaults = self.expandedUserDefaults() {
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
		if let browser = item as? BrowserDelegate {
			let objectValue = browser.objectValue
			let count = browser.children.count
			if count > 0 {
				return NSAttributedString(string:objectValue + " - \(count)", attributes:fontAttributes)
			}
			else {
				return NSAttributedString(string:objectValue, attributes:fontAttributes)
			}
		}
		if let service = item as? ServiceDelegate {
			return NSAttributedString(string:service.objectValue, attributes:boldFontAttributes)
		}
		if let (key, value) = item as? (String, String) {
			let objectValue = NSAttributedString(string:value, attributes:fontAttributes)
			if key.isEmpty {
				return objectValue
			}
			else {
				let mutableString = NSMutableAttributedString(string:key + ": ", attributes:boldFontAttributes)
				mutableString.append(objectValue)
				return mutableString
			}
		}
		fatalError()
	}
	
	func outlineView(_ outlineView:NSOutlineView, pasteboardWriterForItem item:Any) -> NSPasteboardWriting? {
		if let browser = item as? BrowserDelegate {
			let objectValue = browser.objectValue
			let count = browser.children.count
			if count > 0 {
				return objectValue + " - \(count)" as NSString
			}
			else {
				return objectValue as NSString
			}
		}
		if let service = item as? ServiceDelegate {
			return service.objectValue as NSString
		}
		if let (key, value) = item as? (String, String) {
			if key.isEmpty {
				return value as NSString
			}
			else {
				return key + ": " + value as NSString
			}
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
		if let expandedDefaults = expandedUserDefaults() {
			let persistentName = node.persistentName
			if let expandedNumber = expandedDefaults[persistentName] as? NSNumber {
				if expandedNumber.boolValue == expanded {
					return // No change in value
				}
			}
			let newDefaults = expandedDefaults.mutableCopy() as! NSMutableDictionary
			newDefaults[persistentName] = expanded
			UserDefaults.standard.set(newDefaults, forKey:BrowserWindowController.expandedUserDefaultsKey)
		}
		else {
			let persistentName = node.persistentName
			// It's ok to use Swift Dictionary here,
			// because we only have one dictionary key.
			UserDefaults.standard.set([persistentName:expanded], forKey:BrowserWindowController.expandedUserDefaultsKey)
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
			
			if let expandedDefaults = expandedUserDefaults() {
				let newDefaults = NSMutableDictionary()
				for (key, value) in expandedDefaults {
					if let oldKey = key as? String {
						newDefaults[oldKey.lowercased()] = value
					}
				}
				standardUserDefaults.set(newDefaults, forKey:BrowserWindowController.expandedUserDefaultsKey)
			}
		}
	}
	
	private func expandedUserDefaults() -> NSDictionary? {
		// We must use NSDictionary here, because Bonjour uses UTF-8 names,
		// and different UTF-8 strings can be equal in Swift,
		// in which case they would be the same Swift Dictionary key.
		return UserDefaults.standard.object(forKey:BrowserWindowController.expandedUserDefaultsKey) as? NSDictionary
	}
}
