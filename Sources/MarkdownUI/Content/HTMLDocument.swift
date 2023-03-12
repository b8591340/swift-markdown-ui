import Foundation
@_implementationOnly import cmark_gfm
@_implementationOnly import libxml2

final class HTMLDocument {
  struct ParsingOptions: OptionSet {
    var rawValue: Int32

    init(rawValue: Int32) {
      self.rawValue = rawValue
    }

    init(_ htmlParserOption: htmlParserOption) {
      self.rawValue = Int32(htmlParserOption.rawValue)
    }

    static let recover = ParsingOptions(HTML_PARSE_RECOVER)
    static let noError = ParsingOptions(HTML_PARSE_NOERROR)
    static let noWarning = ParsingOptions(HTML_PARSE_NOWARNING)
    static let noBlanks = ParsingOptions(HTML_PARSE_NOBLANKS)
    static let noNetwork = ParsingOptions(HTML_PARSE_NONET)
    static let noImplied = ParsingOptions(HTML_PARSE_NOIMPLIED)
    static let compact = ParsingOptions(HTML_PARSE_COMPACT)

    static let `default`: ParsingOptions = [
      .recover, .noError, .noWarning, .noBlanks, .noNetwork, .compact,
    ]
  }

  final class Node {
    private let nodePtr: htmlNodePtr

    var type: xmlElementType {
      nodePtr.pointee.type
    }

    var name: String? {
      guard let name = nodePtr.pointee.name else { return nil }
      return String(cString: name)
    }

    var isBlockElement: Bool {
      guard
        self.type == XML_ELEMENT_NODE,
        let name = self.name,
        let info = htmlTagLookup(name)
      else {
        return false
      }
      return info.pointee.isinline == 0
    }

    subscript(attribute: String) -> String? {
      guard let value = xmlGetProp(nodePtr, attribute) else {
        return nil
      }
      defer { xmlFree(value) }
      return String(cString: value)
    }

    var content: String? {
      guard let value = xmlNodeGetContent(nodePtr) else {
        return nil
      }
      defer { xmlFree(value) }
      return String(cString: value)
    }

    var children: [Node] {
      guard let first = nodePtr.pointee.children else {
        return []
      }
      return sequence(first: first, next: { $0.pointee.next })
        .map(Node.init(nodePtr:))
        .filter { node in
          (node.type == XML_TEXT_NODE && node.content != "" && node.content != "\n")
            || (node.type == XML_ELEMENT_NODE)
        }
    }

    init(nodePtr: htmlNodePtr) {
      self.nodePtr = nodePtr
    }
  }

  var root: Node? {
    guard let rootPtr = xmlDocGetRootElement(docPtr) else {
      return nil
    }
    return Node(nodePtr: rootPtr)
  }

  var body: Node? {
    root?.children.first { node in
      node.type == XML_ELEMENT_NODE && node.name == "body"
    }
  }

  private let docPtr: htmlDocPtr

  init?(html: String, options: ParsingOptions = .default) {
    guard
      let docPtr = html.cString(using: .utf8)?
        .withUnsafeBufferPointer({ buffer in
          htmlReadMemory(buffer.baseAddress, Int32(buffer.count), nil, nil, options.rawValue)
        })
    else {
      return nil
    }

    self.docPtr = docPtr
  }

  convenience init?(markdown: String, options: ParsingOptions = .default) {
    cmark_gfm_core_extensions_ensure_registered()

    // Create a Markdown parser and attach the GitHub syntax extensions

    let parser = cmark_parser_new(CMARK_OPT_DEFAULT)
    defer { cmark_parser_free(parser) }

    let extensionNames: Set<String>

    if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
      extensionNames = ["autolink", "strikethrough", "tagfilter", "tasklist", "table"]
    } else {
      extensionNames = ["autolink", "strikethrough", "tagfilter", "tasklist"]
    }

    for extensionName in extensionNames {
      guard let syntaxExtension = cmark_find_syntax_extension(extensionName) else {
        continue
      }
      cmark_parser_attach_syntax_extension(parser, syntaxExtension)
    }

    // Parse the Markdown document

    cmark_parser_feed(parser, markdown, markdown.utf8.count)

    guard let document = cmark_parser_finish(parser) else {
      return nil
    }

    // Render the Markdown document to HTML

    let html = String(
      cString: cmark_render_html(
        document,
        CMARK_OPT_NOBREAKS | CMARK_OPT_UNSAFE | CMARK_OPT_GITHUB_PRE_LANG,
        parser?.pointee.syntax_extensions
      )
    )

    self.init(html: html, options: options)
  }

  deinit {
    xmlFreeDoc(docPtr)
  }
}
