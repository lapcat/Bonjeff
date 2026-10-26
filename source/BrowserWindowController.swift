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
	private lazy var fontAttributes:[NSAttributedString.Key:Any] = [.font:font,
																   .foregroundColor:NSColor.controlTextColor,
																   .paragraphStyle:paragraphStyle]
	private lazy var boldFontAttributes:[NSAttributedString.Key:Any] = [.font:NSFont.boldSystemFont(ofSize:fontSize), 
																	   .foregroundColor:NSColor.controlTextColor,
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
	private var baseTitle = ""
	
	// Filtering (Edit > Find > Find…)
	private lazy var findPanelController = FindPanelController()
	private var filterText:String? // nil when not filtering
	private var showsChildrenOfMatches = true
	private var filteredRootChildren = [Any]() // Only valid while filtering
	private var filteredChildren = [ObjectIdentifier:[Any]]() // Only valid while filtering, keyed by node
	private var filterExpandedNodes = Set<ObjectIdentifier>() // Rows the filter has expanded, so refreshes don't re-expand rows the user collapsed
	private var isChangingExpansionProgrammatically = false // Suppresses saving expanded state to user defaults
	
	func open(_ title:String) {
		migrateUserDefaultsIfNecessary()
		browserDelegate.start()
		
		baseTitle = title
		window.center()
		window.setFrameAutosaveName("Browser Window")
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
		outlineView.intercellSpacing = NSMakeSize(3.0, 2.0) // macOS 11 SDK changed the default, so use the old value.
		outlineView.rowHeight = 17.0 // macOS 11 SDK changed the default, so use the old value.
		if #available(macOS 11.0, *) {
			outlineView.setValue(4, forKey:"style") // NSTableViewStylePlain
		}
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
			if self.filterText != nil {
				if let service = object as? ServiceDelegate {
					service.start() // Resolve new services too, so their details can match
				}
				self.scheduleFilterRefresh()
				return
			}
			let parent = self.outlineView.parent(forItem:object)
			self.outlineView.reloadItem(parent, reloadChildren:true)
			if let node = object as? BonjourNode {
				if self.savedExpandedState(of:node) {
					self.outlineView.expandItem(node)
				}
			}
		})
		NotificationCenter.default.addObserver(forName:.nodeDidRemove, object:nil, queue:nil, using:{
			if self.filterText != nil {
				self.scheduleFilterRefresh()
				return
			}
			let object = $0.object
			self.outlineView.reloadItem(object, reloadChildren:true)
		})
		NotificationCenter.default.addObserver(forName:.nodeDidUpdate, object:nil, queue:nil, using:{
			if self.filterText != nil {
				self.scheduleFilterRefresh()
				return
			}
			let object = $0.object
			self.outlineView.reloadItem(object, reloadChildren:true)
		})
		
		window.makeKeyAndOrderFront(self)
	}
	
	func windowWillClose(_ notification:Notification) {
		NSObject.cancelPreviousPerformRequests(withTarget:self)
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
		return visibleChildren(of:item).count
	}
	
	func outlineView(_ outlineView:NSOutlineView, child index:Int, ofItem item:Any?) -> Any {
		return visibleChildren(of:item)[index]
	}
	
	// The children shown in the outline view: all of them, or the filtered ones while filtering.
	private func visibleChildren(of item:Any?) -> [Any] {
		if filterText != nil {
			if item == nil {
				return filteredRootChildren
			}
			if let node = item as? BonjourNode {
				return filteredChildren[ObjectIdentifier(node)] ?? []
			}
			return []
		}
		if item == nil {
			return browserDelegate.children
		}
		if let node = item as? BonjourNode {
			return node.children
		}
		return []
	}
	
	// "_http._tcp. - 12", or "_http._tcp. - 2 of 12" while filtering hides some children
	private func title(of browser:BrowserDelegate) -> String {
		let objectValue = browser.objectValue
		let count = browser.children.count
		if count == 0 {
			return objectValue
		}
		if filterText != nil {
			let visibleCount = visibleChildren(of:browser).count
			if visibleCount != count {
				let format = NSLocalizedString("%@ - %ld of %ld", comment:"Browser row title while filtering: name, visible count, total count")
				return String(format:format, objectValue, visibleCount, count)
			}
		}
		return objectValue + " - \(count)"
	}
	
	func outlineView(_ outlineView:NSOutlineView, objectValueFor tableColumn:NSTableColumn?, byItem item:Any?) -> Any? {
		if tableColumn == nil {
			return nil
		}
		if item == nil {
			return nil
		}
		if let browser = item as? BrowserDelegate {
			return NSAttributedString(string:title(of:browser), attributes:fontAttributes)
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
		preconditionFailure()
	}
	
	func outlineView(_ outlineView:NSOutlineView, pasteboardWriterForItem item:Any) -> NSPasteboardWriting? {
		if let browser = item as? BrowserDelegate {
			return title(of:browser) as NSString
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
		
		// Expansion while filtering is temporary and shouldn't overwrite the saved state
		if filterText == nil && !isChangingExpansionProgrammatically {
			saveNode(node, expanded:true)
		}
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
		
		// While filtering, all services keep resolving so their details can match.
		// They get stopped when the filter is cleared.
		if filterText != nil {
			return
		}
		
		if node is ServiceDelegate {
			node.stop()
		}
		
		if !isChangingExpansionProgrammatically {
			saveNode(node, expanded:false)
		}
	}
	
	// MARK: - Filtering
	
	@objc func showFindPanel(_ sender:Any?) {
		findPanelController.beginSheet(for:window, searchText:filterText ?? "", completion:{ text, showsChildren in
			self.showsChildrenOfMatches = showsChildren
			self.setFilter(text.isEmpty ? nil : text)
		})
	}
	
	@objc func showAllRows(_ sender:Any?) {
		setFilter(nil)
	}
	
	@objc func validateMenuItem(_ menuItem:NSMenuItem) -> Bool {
		if menuItem.action == #selector(showAllRows(_:)) {
			return filterText != nil
		}
		return true
	}
	
	private func setFilter(_ text:String?) {
		NSObject.cancelPreviousPerformRequests(withTarget:self, selector:#selector(refreshFilter), object:nil)
		let wasFiltering = filterText != nil
		filterText = text
		
		if let text = text {
			window.title = baseTitle + " — " + String(format:NSLocalizedString("Filtered by “%@”", comment:"Window title suffix while filtering"), text)
			// Service details are only known once a service is resolved, so resolve all of them.
			// Results that arrive later update the filtered outline via nodeDidUpdate.
			forEachNode(in:browserDelegate.children, { node in
				if let service = node as? ServiceDelegate {
					service.start()
				}
			})
			rebuildFilter(collapsingFirst:true)
		}
		else if wasFiltering {
			window.title = baseTitle
			filteredRootChildren.removeAll()
			filteredChildren.removeAll()
			filterExpandedNodes.removeAll()
			outlineView.reloadData()
			restoreSavedExpansion()
		}
	}
	
	// Coalesces the many updates that arrive while services resolve
	private func scheduleFilterRefresh() {
		NSObject.cancelPreviousPerformRequests(withTarget:self, selector:#selector(refreshFilter), object:nil)
		perform(#selector(refreshFilter), with:nil, afterDelay:0.25)
	}
	
	@objc private func refreshFilter() {
		rebuildFilter(collapsingFirst:false) // Keeps rows the user has expanded or collapsed meanwhile
	}
	
	private func rebuildFilter(collapsingFirst:Bool) {
		if filterText == nil {
			return
		}
		
		var selectedNodes = [BonjourNode]()
		for row in outlineView.selectedRowIndexes {
			if let node = outlineView.item(atRow:row) as? BonjourNode {
				selectedNodes.append(node)
			}
		}
		
		filteredChildren.removeAll()
		var nodesToExpand = [BonjourNode]()
		filteredRootChildren = filteredItems(browserDelegate.children, showAll:false, nodesToExpand:&nodesToExpand)
		
		isChangingExpansionProgrammatically = true
		outlineView.reloadData() // Keeps the expanded state of rows that are still there
		if collapsingFirst {
			outlineView.collapseItem(nil, collapseChildren:true)
			filterExpandedNodes.removeAll()
		}
		var expandedNodes = Set<ObjectIdentifier>()
		for node in nodesToExpand { // Parents come before their children
			let identifier = ObjectIdentifier(node)
			if !filterExpandedNodes.contains(identifier) {
				outlineView.expandItem(node)
			}
			expandedNodes.insert(identifier)
		}
		filterExpandedNodes = expandedNodes // Also drops nodes that are gone
		isChangingExpansionProgrammatically = false
		
		var rows = IndexSet()
		for node in selectedNodes {
			let row = outlineView.row(forItem:node)
			if row >= 0 {
				rows.insert(row)
			}
		}
		outlineView.selectRowIndexes(rows, byExtendingSelection:false)
	}
	
	// Returns the items that stay visible, and fills filteredChildren for every node below them.
	// showAll is true below a matching row when its contents are to be shown.
	// nodesToExpand receives the rows leading to matches (and matching rows whose contents are shown), parents first.
	private func filteredItems(_ items:[Any], showAll:Bool, nodesToExpand:inout [BonjourNode]) -> [Any] {
		var visible = [Any]()
		for item in items {
			let matches = showAll || itemMatchesFilter(item)
			if let node = item as? BonjourNode {
				let expandIndex = nodesToExpand.count
				let children = filteredItems(node.children, showAll:matches && showsChildrenOfMatches, nodesToExpand:&nodesToExpand)
				filteredChildren[ObjectIdentifier(node)] = children
				if !showAll && !children.isEmpty {
					nodesToExpand.insert(node, at:expandIndex)
				}
				if matches || !children.isEmpty {
					visible.append(item)
				}
			}
			else if matches {
				visible.append(item)
			}
		}
		return visible
	}
	
	private func itemMatchesFilter(_ item:Any) -> Bool {
		guard let filterText = filterText else {
			return true
		}
		let text:String
		if let node = item as? BonjourNode {
			text = node.objectValue
		}
		else if let (key, value) = item as? (String, String) {
			text = key.isEmpty ? value : key + ": " + value
		}
		else {
			return false
		}
		return text.range(of:filterText, options:.caseInsensitive) != nil
	}
	
	// Back to the expansion state the user had before filtering
	private func restoreSavedExpansion() {
		isChangingExpansionProgrammatically = true
		outlineView.collapseItem(nil, collapseChildren:true) // Also stops the services that were expanded
		forEachNode(in:browserDelegate.children, { node in
			if savedExpandedState(of:node) {
				outlineView.expandItem(node)
			}
		})
		isChangingExpansionProgrammatically = false
		
		// Stop the services that were only resolved for the search
		forEachNode(in:browserDelegate.children, { node in
			if let service = node as? ServiceDelegate {
				if !outlineView.isItemExpanded(service) {
					service.stop()
				}
			}
		})
	}
	
	// Visits nodes parents first. Leaf rows (key/value pairs) aren't nodes.
	private func forEachNode(in items:[Any], _ body:(BonjourNode) -> Void) {
		for item in items {
			if let node = item as? BonjourNode {
				body(node)
				forEachNode(in:node.children, body)
			}
		}
	}
	
	// MARK: - Expanded state
	
	private func savedExpandedState(of node:BonjourNode) -> Bool {
		if let expandedDefaults = expandedUserDefaults() {
			if let expandedNumber = expandedDefaults[node.persistentName] as? NSNumber {
				return expandedNumber.boolValue
			}
		}
		return node is DomainBrowserDelegate // Expand new domains
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
