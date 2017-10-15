import Cocoa

class DomainBrowserDelegate:BrowserDelegate {
	let domain:String
	var delegates = [ServiceBrowserDelegate]()
	override var children:[Any] { return delegates }
	override var objectValue:String { return domain }
	
	required init(_ domain:String) {
		self.domain = domain
		super.init()
		persistentName = domain.lowercased()
	}
	
	@available(*, unavailable)
	override init() {
		fatalError()
	}
	
	func typeFromService(service:NetService) -> String? {
		let serviceType = service.type
		// e.g. "_tcp.<Domain>".
		// See the explanation below in start()
		// According to the spec, the <Domain> part doesn't matter.
		// Don't check whether it matches, because it may return "local" instead of "members.btmm.icloud.com".
		if let dotIndex = serviceType.index(of:".") {
			if dotIndex > serviceType.startIndex {
				let transport = serviceType[..<dotIndex]
				return String("\(service.name).\(transport).")
			}
		}
		NSLog("ERROR typeFromService:%@", service)
		return nil
	}
	
	override func start() {
		super.start()
		browser.searchForServices(ofType:"_services._dns-sd._udp.", inDomain:domain)
		// A DNS query
		// for PTR records with the name "_services._dns-sd._udp.<Domain>"
		// yields a set of PTR records, where the rdata of each PTR record
		// is the two-label <Service> name, plus the same domain,
		// e.g. "_http._tcp.<Domain>".
		// See https://developer.apple.com/library/content/qa/qa1337/ 
		// and http://files.dns-sd.org/draft-cheshire-dnsext-dns-sd.txt
	}
	
	func netServiceBrowser(_ sender:NetServiceBrowser, didFind service:NetService, moreComing:Bool) {
		guard let type = typeFromService(service:service) else {
			return
		}
		
		for delegate in delegates {
			if delegate.type.caseInsensitiveCompare(type) == .orderedSame {
				NSLog("didFind duplicate service:%@", service)
				return
			}
		}
		
		let newDelegate = ServiceBrowserDelegate(type:type, domain:domain)
		delegates.append(newDelegate)
		delegates.sort { $0.type.localizedCaseInsensitiveCompare($1.type) == .orderedAscending }
		newDelegate.start()
		NotificationCenter.default.post(name:.nodeDidAdd, object:newDelegate)
	}
	
	func netServiceBrowser(_ sender:NetServiceBrowser, didRemove service:NetService, moreComing:Bool) {
		guard let type = typeFromService(service:service) else {
			return
		}
		
		for (index, delegate) in delegates.enumerated() {
			if delegate.type.caseInsensitiveCompare(type) == .orderedSame {
				delegates.remove(at:index)
				delegate.stop()
				NotificationCenter.default.post(name:.nodeDidRemove, object:self)
				return
			}
		}
	}
}

