import Cocoa

// A sheet that asks for the text to filter the browser window by.
class FindPanelController:NSObject {
	private static let showsChildrenUserDefaultsKey = "FindShowsChildrenOfMatches"
	
	// Whether rows below a matching row are shown too. Defaults to true.
	static var showsChildrenOfMatches:Bool {
		get {
			return UserDefaults.standard.object(forKey:showsChildrenUserDefaultsKey) as? Bool ?? true
		}
		set {
			UserDefaults.standard.set(newValue, forKey:showsChildrenUserDefaultsKey)
		}
	}
	
	private let panel:NSPanel = {
		let contentRect = NSMakeRect(0.0, 0.0, 360.0, 160.0)
		let panel = NSPanel(contentRect:contentRect, styleMask:[.titled], backing:.buffered, defer:true)
		panel.isReleasedWhenClosed = false
		return panel
	}()
	private let searchField = NSTextField(string:"")
	private let childrenCheckbox = NSButton(checkboxWithTitle:NSLocalizedString("Also show the contents of matching rows", comment:"Find sheet checkbox"), target:nil, action:nil)
	private var completion:((String, Bool) -> Void)?
	
	override init() {
		super.init()
		buildContent()
	}
	
	// The completion handler is called only when the user clicks Find, with the search text and the checkbox state.
	func beginSheet(for window:NSWindow, searchText:String, completion:@escaping (String, Bool) -> Void) {
		if window.attachedSheet != nil {
			return
		}
		self.completion = completion
		searchField.stringValue = searchText
		childrenCheckbox.state = FindPanelController.showsChildrenOfMatches ? .on : .off
		window.beginSheet(panel, completionHandler:{ response in
			let completion = self.completion
			self.completion = nil
			if response == .OK {
				let showsChildren = self.childrenCheckbox.state == .on
				FindPanelController.showsChildrenOfMatches = showsChildren
				completion?(self.searchField.stringValue, showsChildren)
			}
		})
		panel.makeFirstResponder(searchField)
		searchField.selectText(nil)
	}
	
	@objc private func find(_ sender:Any?) {
		endSheet(returnCode:.OK)
	}
	
	@objc private func cancel(_ sender:Any?) {
		endSheet(returnCode:.cancel)
	}
	
	private func endSheet(returnCode:NSApplication.ModalResponse) {
		if let parent = panel.sheetParent {
			parent.endSheet(panel, returnCode:returnCode)
		}
	}
	
	private func buildContent() {
		panel.title = NSLocalizedString("Find", comment:"Find sheet title")
		
		let label = NSTextField(labelWithString:NSLocalizedString("Show rows containing:", comment:"Find sheet label"))
		
		searchField.placeholderString = NSLocalizedString("Text to find (not case-sensitive)", comment:"Find sheet placeholder")
		searchField.usesSingleLineMode = true
		searchField.cell?.isScrollable = true
		searchField.cell?.wraps = false
		
		let cancelButton = NSButton(title:NSLocalizedString("Cancel", comment:"Cancel button"), target:self, action:#selector(cancel(_:)))
		cancelButton.keyEquivalent = "\u{1b}" // Escape
		
		let findButton = NSButton(title:NSLocalizedString("Find", comment:"Find button"), target:self, action:#selector(find(_:)))
		findButton.keyEquivalent = "\r" // Default button, so Return activates it
		
		let contentView:NSView = panel.contentView!
		for view in [label, searchField, childrenCheckbox, cancelButton, findButton] as [NSView] {
			view.translatesAutoresizingMaskIntoConstraints = false
			contentView.addSubview(view)
		}
		
		NSLayoutConstraint.activate([
			label.topAnchor.constraint(equalTo:contentView.topAnchor, constant:20.0),
			label.leadingAnchor.constraint(equalTo:contentView.leadingAnchor, constant:20.0),
			label.trailingAnchor.constraint(lessThanOrEqualTo:contentView.trailingAnchor, constant:-20.0),
			
			searchField.topAnchor.constraint(equalTo:label.bottomAnchor, constant:8.0),
			searchField.leadingAnchor.constraint(equalTo:contentView.leadingAnchor, constant:20.0),
			searchField.trailingAnchor.constraint(equalTo:contentView.trailingAnchor, constant:-20.0),
			searchField.widthAnchor.constraint(greaterThanOrEqualToConstant:320.0),
			
			childrenCheckbox.topAnchor.constraint(equalTo:searchField.bottomAnchor, constant:12.0),
			childrenCheckbox.leadingAnchor.constraint(equalTo:contentView.leadingAnchor, constant:20.0),
			childrenCheckbox.trailingAnchor.constraint(lessThanOrEqualTo:contentView.trailingAnchor, constant:-20.0),
			
			findButton.topAnchor.constraint(equalTo:childrenCheckbox.bottomAnchor, constant:20.0),
			findButton.trailingAnchor.constraint(equalTo:contentView.trailingAnchor, constant:-20.0),
			findButton.bottomAnchor.constraint(equalTo:contentView.bottomAnchor, constant:-20.0),
			findButton.widthAnchor.constraint(greaterThanOrEqualToConstant:80.0),
			
			cancelButton.trailingAnchor.constraint(equalTo:findButton.leadingAnchor, constant:-12.0),
			cancelButton.firstBaselineAnchor.constraint(equalTo:findButton.firstBaselineAnchor),
			cancelButton.widthAnchor.constraint(equalTo:findButton.widthAnchor)
			])
		
		panel.initialFirstResponder = searchField
		contentView.layoutSubtreeIfNeeded()
		panel.setContentSize(contentView.fittingSize)
	}
}
