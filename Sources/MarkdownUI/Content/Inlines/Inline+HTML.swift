import Foundation
@_implementationOnly import libxml2

extension Inline {
  init?(htmlNode: HTMLDocument.Node) {
    switch htmlNode.type {
    case XML_TEXT_NODE:
      guard
        let content = htmlNode.content?.trimmingCharacters(in: .newlines),
        !content.isEmpty
      else {
        return nil
      }
      self = content == " " ? .softBreak : .text(content)
    case XML_ELEMENT_NODE:
      guard let name = htmlNode.name else { return nil }

      switch name {
      case "br":
        self = .lineBreak
      case "code":
        self = .code(htmlNode.content ?? "")
      case "em":
        self = .emphasis(htmlNode.children.compactMap(Inline.init(htmlNode:)))
      case "strong":
        self = .strong(htmlNode.children.compactMap(Inline.init(htmlNode:)))
      case "del":
        self = .strikethrough(htmlNode.children.compactMap(Inline.init(htmlNode:)))
      case "a":
        self = .link(
          destination: htmlNode["href"] ?? "",
          children: htmlNode.children.compactMap(Inline.init(htmlNode:))
        )
      case "img":
        self = .image(
          source: htmlNode["src"] ?? "",
          // TODO: width and height?
          // TODO: replace children with alt
          children: htmlNode["alt"].map { [.text($0)] } ?? []
        )
      default:
        // TODO: add unknown node if there are any children, otherwise resolve to text node
        guard let content = htmlNode.content, !content.isEmpty else {
          return nil
        }
        self = .text(content)
      }
    default:
      return nil
    }
  }
}
