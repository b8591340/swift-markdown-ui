import Foundation
@_implementationOnly import cmark_gfm

enum Inline: Hashable {
  case text(String)
  case softBreak
  case lineBreak
  case code(String)
  case html(String)
  case emphasis([Inline])
  case strong([Inline])
  case strikethrough([Inline])
  case link(destination: String, children: [Inline])
  case image(source: String, children: [Inline])
}

extension Sequence where Iterator.Element == Inline {
  var text: String {
    self.collect { inline in
      guard case .text(let value) = inline else {
        return []
      }
      return [value]
    }
    .joined()
  }

  func apply(_ transform: (Inline) throws -> [Inline]) rethrows -> [Inline] {
    try self.flatMap { try $0.apply(transform) }
  }

  func collect<Value>(_ collect: (Inline) throws -> [Value]) rethrows -> [Value] {
    try self.flatMap { try $0.collect(collect) }
  }
}

extension Inline {
  func apply(_ transform: (Inline) throws -> [Inline]) rethrows -> [Inline] {
    switch self {
    case .text, .softBreak, .lineBreak, .code, .html:
      return try transform(self)
    case .emphasis(let children):
      return try transform(.emphasis(children.apply(transform)))
    case .strong(let children):
      return try transform(.strong(children.apply(transform)))
    case .strikethrough(let children):
      return try transform(.strikethrough(children.apply(transform)))
    case .link(let destination, let children):
      return try transform(.link(destination: destination, children: children.apply(transform)))
    case .image(let source, let children):
      return try transform(.image(source: source, children: children.apply(transform)))
    }
  }

  func collect<Value>(_ collect: (Inline) throws -> [Value]) rethrows -> [Value] {
    var values: [Value]

    switch self {
    case .text, .softBreak, .lineBreak, .code, .html:
      values = []
    case .emphasis(let children):
      values = try children.collect(collect)
    case .strong(let children):
      values = try children.collect(collect)
    case .strikethrough(let children):
      values = try children.collect(collect)
    case .link(_, let children):
      values = try children.collect(collect)
    case .image(_, let children):
      values = try children.collect(collect)
    }

    values.append(contentsOf: try collect(self))
    return values
  }
}

extension Inline {
  init?(node: CommonMarkNode) {
    switch node.type {
    case CMARK_NODE_TEXT:
      self = .text(node.literal!)
    case CMARK_NODE_SOFTBREAK:
      self = .softBreak
    case CMARK_NODE_LINEBREAK:
      self = .lineBreak
    case CMARK_NODE_CODE:
      self = .code(node.literal!)
    case CMARK_NODE_HTML_INLINE:
      self = .html(node.literal!)
    case CMARK_NODE_EMPH:
      self = .emphasis(node.children.compactMap(Inline.init(node:)))
    case CMARK_NODE_STRONG:
      self = .strong(node.children.compactMap(Inline.init(node:)))
    case CMARK_NODE_STRIKETHROUGH:
      self = .strikethrough(node.children.compactMap(Inline.init(node:)))
    case CMARK_NODE_LINK:
      self = .link(
        destination: node.url ?? "",
        children: node.children.compactMap(Inline.init(node:))
      )
    case CMARK_NODE_IMAGE:
      self = .image(
        source: node.url ?? "",
        children: node.children.compactMap(Inline.init(node:))
      )
    default:
      assertionFailure("Unknown inline type '\(node.typeString)'")
      return nil
    }
  }
}

extension Inline {
  struct Image: Hashable {
    var source: String?
    var alt: String
    var destination: String?
  }

  var image: Image? {
    switch self {
    case let .image(source, children):
      return .init(source: source, alt: children.text)
    case let .link(destination, children) where children.count == 1:
      guard case let .some(.image(source, children)) = children.first else {
        return nil
      }
      return .init(source: source, alt: children.text, destination: destination)
    default:
      return nil
    }
  }
}
