//
//  SiteCheckPublishPlugin.swift
//
//
//  Created by Stephen Hume on 2021-05-06.
//

import AsyncHTTPClient
import Foundation
import Publish
import Files
import SwiftSoup
import Logging

class LinkStatus: Codable {
  var link: URL
  var firstFound: Date
  var lastFound: Date
  var lastFileSeen: Path?
  var lastCheck: Date?
  var redirectURL: URL?
  init(link: URL, path: Path) {
    self.link = link
    self.firstFound = Date()
    self.lastFound = self.firstFound
    self.lastFileSeen = path
  }

}
public var allowedMailAddresses: Set<String> = []
public var logger = Logger(label: "publishsite.main")
public var maxLinksToCheckPerScan = 3

typealias ArchiveDict = [String: LinkStatus]
var linksKnown: ArchiveDict = [:]
var newLinksFound: Set<String> = []
var scanDate: Date = Date()
var httpClient: HTTPClient? = nil
public func loadArchiveLinks() {
  if (thisFile?.parent!.containsFile(at: "Reports/linkarchive.json")) != nil {
    if let archivedata = try? thisFile?.parent!.file(at: "Reports/linkarchive.json").read() {
      let decoder = JSONDecoder()
      if #available(macOS 10.12, *) {
        decoder.dateDecodingStrategy = .iso8601
      } else {
        // Fallback on earlier versions
      }
      linksKnown = try! decoder.decode(ArchiveDict.self, from: archivedata)
    }
  }
}
@available(macOS 10.12, *)
public func archiveLinks() {
  if !linksKnown.isEmpty {
    let encoder = JSONEncoder()
    if #available(macOS 10.15, *) {
      encoder.outputFormatting = .withoutEscapingSlashes
    } else {
      encoder.outputFormatting = .prettyPrinted  // seems mutually exclusive with new slashes setting
    }
    encoder.dateEncodingStrategy = .iso8601

    if let data = try? encoder.encode(linksKnown) {
      //            print(String(data: data, encoding: .utf8)!)
      try! thisFile?.parent!.createFileIfNeeded(at: "Reports/linkarchive.json").write(data)
    }
  }

}
func linkStatusSort(
  _ lhs: (key1: String, val1: LinkStatus), _ rhs: (key2: String, val2: LinkStatus)
) -> Bool {
  if lhs.val1.lastFound < rhs.val2.lastFound {
    return false  // want links still in use checked before really old ones
  } else if lhs.val1.firstFound < rhs.val2.firstFound {
    return false  // want links just found to get checked first
  } else if rhs.val2.lastCheck == nil {
    return true  // if no check yet then keep at top of the list to check
  } else if lhs.val1.lastCheck == nil {
    return true  // if no check yet then keep at top of the list to check
  } else if lhs.val1.lastCheck! < rhs.val2.lastCheck! {  // force unwrap should be OK here due to the previous nil checks
    return true
  }
  return true
}

public func checkSomeLinks() {
  if !linksKnown.isEmpty {
    let linksToCheck = linksKnown.sorted(by: linkStatusSort)
    httpClient = HTTPClient(eventLoopGroupProvider: .createNew,
                            configuration: HTTPClient.Configuration(redirectConfiguration: .disallow))

    let range = 0...(min(maxLinksToCheckPerScan, linksToCheck.count))
    for indx in range {
      logger.debug("\(linksToCheck[indx].1.link.absoluteString)")

      if let response = try? httpClient!.get(url: linksToCheck[indx].1.link.absoluteString).wait()
      {  //, logger: logger

        if response.status == .ok {
          // handle response
          logger.debug("👍🏻\(linksToCheck[indx].0)")
          linksKnown[linksToCheck[indx].0]?.lastCheck = Date()
        } else {
          logger.warning(
            "\(response.status) Link check failed❓: \(linksToCheck[indx].1.link.absoluteString)")  // should append this to a log to investigate
        }
      }
    }
    try? httpClient?.syncShutdown()
  }
}

@available(macOS 10.11, *)
public extension Plugin {
  static var pageScan: Self {
    Plugin(name: "Collect all the published links") { context in
      if linksKnown.isEmpty {
        loadArchiveLinks()
      }
      try context.outputFolder(at: "").subfolders.recursive.forEach { folder in
        let prefixLength = try context.outputFolder(at: "").path.count
        for file in folder.files {

          if file.extension == "html" {
            do {
              let path = Path(String(file.path.dropFirst(prefixLength)))
              let justDirPath = URL(string: path.string)?.deletingLastPathComponent()
              let htmlPage = try file.readAsString()
              let doc: Document = try SwiftSoup.parse(htmlPage)
              let links: Elements = try doc.select("a")
              for link in links {
                let linkHref: String = try link.attr("href")  // "http://example.com/"
                if linkHref.hasPrefix("#") {
                  // markdown uses a trick to imbed internal page links so they are not always id values
                  let foundID: Element? = try doc.getElementById(String(linkHref.dropFirst()))
                  if foundID == nil {
                    let foundName: Element? = try doc.select("a[name=\(linkHref.dropFirst())]")
                      .first()
                    if foundName == nil {
                      logger.warning("Missing markdown link name=\(linkHref.dropFirst())")
                    }
                  }
                  continue
                }
                let linkOuterH: String = try link.outerHtml()  // "<a href="http://example.com"><b>example</b></a>"

                if let urla = URL(string: linkHref) {
                  if let scem = urla.scheme {
                    if scem.starts(with: "https") {
                      if urla.absoluteString != linkHref {
                        logger.warning("Warning: URL and href do not match \(linkOuterH)")

                      }

                    } else if scem.starts(with: "mailto") {

                      // check against valid email list
                      if allowedMailAddresses.contains(urla.absoluteString) {
                        continue
                      }
                      logger.warning("Warning this is not in allowed list: mailto:  \(linkOuterH)")
                      continue
                    } else {

                      logger.warning(
                        "Warning:\(urla.scheme ?? "???"): Path: \(path)  \(linkOuterH)")
                    }
                    // now save in links set
                    if let lnkStatus = linksKnown[urla.absoluteString] {
                      lnkStatus.lastFound = scanDate
                      lnkStatus.lastFileSeen = path

                    } else {
                      logger.info("https: \(linkOuterH)")
                      newLinksFound.insert(urla.absoluteString)  // this can help start a link check keeping set of new members.
                      linksKnown[urla.absoluteString] = LinkStatus(link: urla, path: path)
                    }

                  } else {
                    var pathToCheck = justDirPath!
                    if linkHref != "/" {
                      if linkHref.first == "/" {
                        pathToCheck = URL(string: linkHref)!
                        if pathToCheck.pathExtension.isEmpty {
                          pathToCheck = pathToCheck.appendingPathComponent("index.html")
                        }
                      }
//                      pathToCheck = URL(fileURLWithPath: linkHref, relativeTo: justDirPath)
                     else if linkHref.last != "/" {
                        pathToCheck = pathToCheck.appendingPathComponent(linkHref)
                        if pathToCheck.pathExtension.isEmpty {
                        logger.warning(
                          """
                          Check if path should have trailing slash: \(linkHref)
                          """)
                        }
                      }else {
                        pathToCheck = pathToCheck.appendingPathComponent(linkHref).appendingPathComponent("index.html")
                      }
                    }
                    if pathToCheck.pathExtension.isEmpty {
                      pathToCheck = pathToCheck.appendingPathComponent("index.html")
                    }
                    if (try? context.outputFile(at: Path(pathToCheck.absoluteString))) != nil {
                      
                      continue
                    } else {
                      logger.warning(
                        """
                        Cannot locate: \(String(describing: pathToCheck))
                        """)
                    }
                  }
                } else {
                  if let _ = try? link.attr("name") {

                    continue
                  }
                  logger.debug("???:  \(linkOuterH)")
                }
                //                        let text: String = try link.parent()!.text(); // "An example link"
                //
                //                        let linkText: String = try link.text(); // "example""
                //
                //                        let linkInnerH: String = try link.html(); // "<b>example</b>"
                //                        print(linkOuterH)
              }

            } catch Exception.Error(_, let message) {
              print(message)
            } catch {
              print("error")
            }
          }
        }
      }
    }

  }
}
