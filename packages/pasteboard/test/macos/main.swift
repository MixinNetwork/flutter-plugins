import AppKit

// Exercise the plugin with a private pasteboard, leaving the user's clipboard untouched.
let pasteboard = NSPasteboard.withUniqueName()
defer { pasteboard.releaseGlobally() }
let plugin = PasteboardPlugin()

func expectFiles(_ urls: [NSURL], _ expected: [String], scenario: String) {
  pasteboard.clearContents()
  precondition(pasteboard.writeObjects(urls), "Could not write fixture: \(scenario)")
  var didReply = false
  plugin.files(result: { value in
    didReply = true
    let actual = value as? [String] ?? []
    precondition(actual == expected, "\(scenario): expected \(expected), got \(actual)")
  }, pasteboard: pasteboard)
  precondition(didReply, "Missing result: \(scenario)")
  print("PASS: \(scenario)")
}

let localPaths = ["/tmp/pasteboard ordinary.txt", "/tmp/剪贴板 #100% + café.txt"]
let localURLs = localPaths.map { NSURL(fileURLWithPath: $0) }
let webURLs = [
  NSURL(string: "https://example.com/etc/hosts")!,
  NSURL(string: "http://example.com/tmp/file.txt")!,
  NSURL(string: "ftp://example.com/etc/passwd")!,
]

expectFiles(webURLs, [], scenario: "exclude non-file URLs")
expectFiles(localURLs, localPaths, scenario: "preserve local paths and special characters")
expectFiles([webURLs[0], localURLs[0], webURLs[1], localURLs[1]], localPaths,
            scenario: "filter mixed URLs while preserving file order")

pasteboard.clearContents()
var emptyResult: [String]?
plugin.files(result: { emptyResult = $0 as? [String] }, pasteboard: pasteboard)
precondition(emptyResult == nil || emptyResult == [], "Empty pasteboard must not return files")
print("PASS: empty pasteboard")
