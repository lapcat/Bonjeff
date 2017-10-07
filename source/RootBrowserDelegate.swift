import Cocoa

class RootBrowserDelegate:BrowserDelegate {
	var delegates = [DomainBrowserDelegate]()
	override var children:[Any] { return delegates }

	override func start() {
		super.start()
		browser.searchForBrowsableDomains()
	}
	
	func netServiceBrowser(_ sender:NetServiceBrowser, didFindDomain domain:String, moreComing:Bool) {
		for delegate in delegates {
			if delegate.domain == domain {
				NSLog("didFind duplicate domain:%@", domain)
				return
			}
		}
		
		let newDelegate = DomainBrowserDelegate(domain)
		delegates.append(newDelegate)
		delegates.sort { $0.domain < $1.domain }
		newDelegate.start()
		NotificationCenter.default.post(name:.nodeDidAdd, object:newDelegate)
	}
	
	func netServiceBrowser(_ sender:NetServiceBrowser, didRemoveDomain domain:String, moreComing:Bool) {
		for (index, delegate) in delegates.enumerated() {
			if delegate.domain == domain {
				delegates.remove(at:index)
				delegate.stop()
				NotificationCenter.default.post(name:.nodeDidRemove, object:nil) // nil is root item for outline view
				return
			}
		}
	}
}
