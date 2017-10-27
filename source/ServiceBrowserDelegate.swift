import Cocoa

class ServiceBrowserDelegate:BrowserDelegate {
	let domain:String
	let type:String
	var delegates = [ServiceDelegate]()
	override var children:[Any] { return delegates }
	override lazy var objectValue:String = type
	override lazy var persistentName:String = {
		let name = type + domain
		return name.lowercased()
	}()
	
	required init(type:String, domain:String) {
		self.type = type
		self.domain = domain
		super.init()
	}
	
	@available(*, unavailable)
	override init() {
		fatalError()
	}
	
	override func start() {
		super.start()
		browser.searchForServices(ofType:type, inDomain:domain)
	}
	
	func netServiceBrowser(_ sender:NetServiceBrowser, didFind service:NetService, moreComing:Bool) {
		for delegate in delegates {
			if delegate.service == service {
				NSLog("didFind duplicate service:%@", service)
				return
			}
		}
		
		let newDelegate = ServiceDelegate(service)
		delegates.append(newDelegate)
		delegates.sort { $0.service.name.localizedCaseInsensitiveCompare($1.service.name) == .orderedAscending }
		NotificationCenter.default.post(name:.nodeDidAdd, object:newDelegate)
	}
	
	func netServiceBrowser(_ sender:NetServiceBrowser, didRemove service:NetService, moreComing:Bool) {
		for (index, delegate) in delegates.enumerated() {
			if delegate.service == service {
				delegates.remove(at:index)
				delegate.stop()
				NotificationCenter.default.post(name:.nodeDidRemove, object:self)
				return
			}
		}
	}
}

