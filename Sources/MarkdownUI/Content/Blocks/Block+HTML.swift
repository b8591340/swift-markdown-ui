import Foundation
@_implementationOnly import libxml2

extension Block {
  init?(htmlNode: HTMLDocument.Node) {
    guard htmlNode.type == XML_ELEMENT_NODE, let name = htmlNode.name else {
      return nil
    }

    switch name {
    case "blockquote":
      self = .blockquote(htmlNode.children.compactMap(Block.init(htmlNode:)))
    case "ul" where htmlNode.hasTaskListItems, "ol" where htmlNode.hasTaskListItems:
      self = .taskList(
        tight: htmlNode.isTightList,
        items: htmlNode.children.compactMap(TaskListItem.init(htmlNode:))
      )
    case "ul":
      self = .bulletedList(
        tight: htmlNode.isTightList,
        items: htmlNode.children.compactMap(ListItem.init(htmlNode:))
      )
    case "ol":
      self = .numberedList(
        tight: htmlNode.isTightList,
        start: htmlNode.listStart ?? 1,
        items: htmlNode.children.compactMap(ListItem.init(htmlNode:))
      )
    case "pre":
      self = .codeBlock(
        info: htmlNode["lang"],
        content: htmlNode.content ?? ""
      )
    case "p":
      self = .paragraph(htmlNode.children.compactMap(Inline.init(htmlNode:)))
    case "h1":
      self = .heading(level: 1, text: htmlNode.children.compactMap(Inline.init(htmlNode:)))
    case "h2":
      self = .heading(level: 2, text: htmlNode.children.compactMap(Inline.init(htmlNode:)))
    case "h3":
      self = .heading(level: 3, text: htmlNode.children.compactMap(Inline.init(htmlNode:)))
    case "h4":
      self = .heading(level: 4, text: htmlNode.children.compactMap(Inline.init(htmlNode:)))
    case "h5":
      self = .heading(level: 5, text: htmlNode.children.compactMap(Inline.init(htmlNode:)))
    case "h6":
      self = .heading(level: 6, text: htmlNode.children.compactMap(Inline.init(htmlNode:)))
    case "table":
      // TODO: implement
      return nil
    case "hr":
      self = .thematicBreak
    default:
      guard let content = htmlNode.content, !content.isEmpty else { return nil }
      self = .paragraph([.text(content)])
    }
  }
}

extension Array where Element == Block {
  init(markdown: String) {
    let document = HTMLDocument(markdown: markdown)
    let blocks = document?.body?.children.compactMap(Block.init(htmlNode:)) ?? []

    self.init(blocks)
  }
}

extension HTMLDocument.Node {
  fileprivate var hasTaskListItems: Bool {
    self.children.contains { $0.isTaskListItem }
  }

  fileprivate var isTaskListItem: Bool {
    guard self.type == XML_ELEMENT_NODE, self.name == "li" else {
      return false
    }

    return self.children.first { node in
      node.name == "input" || (node.name == "p" && node.children.first?.name == "input")
    } != nil
  }

  fileprivate var isTaskListItemChecked: Bool {
    guard self.type == XML_ELEMENT_NODE, self.name == "li" else {
      return false
    }
    return children.first?["checked"] != nil || children.first?.children.first?["checked"] != nil
  }

  fileprivate var isTightList: Bool {
    guard self.type == XML_ELEMENT_NODE, self.name == "ul" || self.name == "ol" else {
      return false
    }
    return children.first?.children.first?.name != "p"
  }

  fileprivate var listStart: Int? {
    guard self.type == XML_ELEMENT_NODE, self.name == "ol", let value = self["start"] else {
      return nil
    }
    return Int(value)
  }

  fileprivate var listItemBlocks: [Block] {
    guard self.type == XML_ELEMENT_NODE, self.name == "li" else {
      return []
    }

    // wrap inlines into a paragraph
    var paragraph: Block?

    let inlines = self.children
      .prefix { !$0.isBlockElement }
      .compactMap(Inline.init(htmlNode:))

    if !inlines.isEmpty {
      paragraph = .paragraph(inlines)
    }

    // get the remaining blocks
    let blocks = self.children
      .drop { !$0.isBlockElement }
      .compactMap(Block.init(htmlNode:))

    return [paragraph].compactMap { $0 } + blocks
  }
}

extension TaskListItem {
  fileprivate init?(htmlNode: HTMLDocument.Node) {
    guard htmlNode.type == XML_ELEMENT_NODE, htmlNode.name == "li" else {
      return nil
    }
    self.init(
      isCompleted: htmlNode.isTaskListItemChecked,
      blocks: htmlNode.listItemBlocks.trimmingLeadingWhitespace()
    )
  }
}

extension ListItem {
  fileprivate init?(htmlNode: HTMLDocument.Node) {
    guard htmlNode.type == XML_ELEMENT_NODE, htmlNode.name == "li" else {
      return nil
    }
    self.init(blocks: htmlNode.listItemBlocks)
  }
}

extension Array where Element == Block {
  fileprivate func trimmingLeadingWhitespace() -> Self {
    guard case .paragraph(let inlines) = self.first else {
      return self
    }

    var result = self
    result[0] = .paragraph(inlines.trimmingLeadingWhitespace())
    return result
  }
}

extension Array where Element == Inline {
  fileprivate func trimmingLeadingWhitespace() -> Self {
    guard case .text(let value) = self.first else {
      return self
    }

    var result = self
    result[0] = .text(String(value.drop(while: \.isWhitespace)))
    return result
  }
}
