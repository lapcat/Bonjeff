import Cocoa

class LicenseWindowController {
	static var licenseWindow:NSWindow?
	
	static func open() {
		if let window = licenseWindow {
			window.makeKeyAndOrderFront(nil)
			return
		}
		
		guard let myURL = Bundle.main.url(forResource:"LICENSE", withExtension:"txt") else {
			NSLog("LICENSE.txt not found")
			return
		}
		
		do {
			let license = try NSAttributedString(url:myURL, options:[:], documentAttributes:nil)
			showWindow(license)
		}
		catch {
			NSLog("License error: %@", error as NSError)
		}
	}
	
	static func showWindow(_ license:NSAttributedString) {
		let label = NSTextField(labelWithAttributedString:license)
		label.lineBreakMode = .byWordWrapping
		label.usesSingleLineMode = false
		label.translatesAutoresizingMaskIntoConstraints = false
		
		let styleMask:NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
		let window = NSWindow(contentRect:label.frame, styleMask:styleMask, backing:.buffered, defer:true)
		window.isReleasedWhenClosed = false
		window.tabbingMode = .disallowed
		window.title = NSLocalizedString("License", comment:"License window")
		
		let contentView = window.contentView!
		contentView.addSubview(label)
		
		NSLayoutConstraint.activate([
			label.topAnchor.constraint(equalTo:contentView.topAnchor, constant:10.0),
			label.bottomAnchor.constraint(equalTo:contentView.bottomAnchor, constant:-10.0),
			label.leadingAnchor.constraint(equalTo:contentView.leadingAnchor, constant:10.0),
			label.trailingAnchor.constraint(equalTo:contentView.trailingAnchor, constant:-10.0),
			label.widthAnchor.constraint(equalToConstant:400.0)
			])
		
		window.makeKeyAndOrderFront(nil)
		window.center() // Wait until after makeKeyAndOrderFront so the window sizes properly first
		
		licenseWindow = window
		
		var observer:NSObjectProtocol?
		observer = NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification, object:licenseWindow, queue:nil, using:{_ in
			if let token = observer {
				NotificationCenter.default.removeObserver(token)
			}
			licenseWindow = nil
		})
	}
}
