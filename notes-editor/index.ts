import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
import Blockquote from "@tiptap/extension-blockquote";
import { Node as ProseMirrorNode } from "@tiptap/pm/model";
import {
  MarkdownParser,
  MarkdownSerializer,
  defaultMarkdownParser,
  defaultMarkdownSerializer,
} from "@tiptap/pm/markdown";

declare global {
  interface Window {
    VersoNotesInit?: () => void;
    VersoNotesSetContent?: (markdown: string) => void;
    VersoNotesGetMarkdown?: () => string;
    VersoNotesInsertQuote?: (quote: string, annotationId: string) => void;
  }
}

// Regex to extract annotation ID from markdown blockquote
// Format: > [[q:uuid]] Quote text
const QUOTE_MARKER_REGEX = /^\[\[q:([a-f0-9-]+)\]\]\s*/i;

// Custom Blockquote extension with annotationId attribute
const CustomBlockquote = Blockquote.extend({
  addAttributes() {
    return {
      annotationId: {
        default: null,
        parseHTML: (element) => element.getAttribute("data-annotation-id"),
        renderHTML: (attributes) => {
          if (!attributes.annotationId) {
            return {};
          }
          return { "data-annotation-id": attributes.annotationId };
        },
      },
    };
  },
});

let editorInstance: Editor | null = null;
let isApplyingContent = false;
let updateTimer: ReturnType<typeof setTimeout> | null = null;
let markdownParser: MarkdownParser | null = null;
let markdownSerializer: MarkdownSerializer | null = null;

const nameMap: Record<string, string> = {
  list_item: "listItem",
  bullet_list: "bulletList",
  ordered_list: "orderedList",
  code_block: "codeBlock",
  horizontal_rule: "horizontalRule",
  hard_break: "hardBreak",
};

const remapSpec = (spec: any, schema: any) => {
  if (spec.block && nameMap[spec.block]) {
    spec.block = nameMap[spec.block];
  }
  if (spec.node && nameMap[spec.node]) {
    spec.node = nameMap[spec.node];
  }
  if (spec.mark && nameMap[spec.mark]) {
    spec.mark = nameMap[spec.mark];
  }
  if (spec.block && !schema.nodes[spec.block]) {
    return null;
  }
  if (spec.node && !schema.nodes[spec.node]) {
    return null;
  }
  if (spec.mark && !schema.marks[spec.mark]) {
    return null;
  }
  return spec;
};

const postMessage = (payload: Record<string, unknown>) => {
  if (window.webkit?.messageHandlers?.notes) {
    window.webkit.messageHandlers.notes.postMessage(payload);
  }
};

const scheduleMarkdownPost = () => {
  if (!editorInstance || isApplyingContent) {
    return;
  }
  if (updateTimer) {
    clearTimeout(updateTimer);
  }
  updateTimer = setTimeout(() => {
    if (!editorInstance || isApplyingContent) {
      return;
    }
    if (!markdownSerializer) {
      return;
    }
    const markdown = markdownSerializer.serialize(editorInstance.state.doc);
    postMessage({ type: "markdown", markdown });
  }, 400);
};

// Find the blockquote node at a given position
const findBlockquoteAt = (
  doc: ProseMirrorNode,
  pos: number
): { node: ProseMirrorNode; pos: number } | null => {
  let result: { node: ProseMirrorNode; pos: number } | null = null;
  doc.nodesBetween(0, doc.content.size, (node, nodePos) => {
    if (node.type.name === "blockquote") {
      if (nodePos <= pos && pos <= nodePos + node.nodeSize) {
        result = { node, pos: nodePos };
        return false; // Stop searching
      }
    }
    return true;
  });
  return result;
};

const initEditor = () => {
  const host = document.querySelector("#editor") as HTMLElement | null;
  if (!host) {
    return;
  }

  if (editorInstance) {
    editorInstance.destroy();
    editorInstance = null;
  }

  editorInstance = new Editor({
    element: host,
    extensions: [
      StarterKit.configure({
        heading: { levels: [1, 2, 3] },
        blockquote: false, // Disable default blockquote
      }),
      CustomBlockquote, // Use our custom blockquote
      Placeholder.configure({
        placeholder: "Start typing...",
      }),
    ],
    editorProps: {
      attributes: {
        spellcheck: "true",
        autocapitalize: "sentences",
        autocorrect: "on",
      },
      handleClick(view, pos, event) {
        // Find blockquote at click position
        const found = findBlockquoteAt(view.state.doc, pos);
        if (!found) return false;

        const annotationId = found.node.attrs.annotationId;
        if (annotationId) {
          event.preventDefault();
          postMessage({ type: "quote-click", annotationId });
          return true;
        }
        return false;
      },
    },
    onUpdate: () => {
      scheduleMarkdownPost();
    },
  });

  // Build custom markdown parser
  const remappedTokens = Object.fromEntries(
    Object.entries(defaultMarkdownParser.tokens)
      .map(([key, value]) => [key, remapSpec({ ...value }, editorInstance!.schema)])
      .filter(([, value]) => value !== null)
  );
  markdownParser = new MarkdownParser(
    editorInstance.schema,
    defaultMarkdownParser.tokenizer,
    remappedTokens
  );

  // Build custom markdown serializer with annotationId support
  const remappedNodes: Record<string, any> = { ...defaultMarkdownSerializer.nodes };
  for (const [from, to] of Object.entries(nameMap)) {
    if (remappedNodes[from] && !remappedNodes[to]) {
      remappedNodes[to] = remappedNodes[from];
      delete remappedNodes[from];
    }
  }
  for (const key of Object.keys(remappedNodes)) {
    if (!editorInstance.schema.nodes[key]) {
      delete remappedNodes[key];
    }
  }

  // Custom blockquote serializer that includes [[q:uuid]] marker
  remappedNodes.blockquote = (state: any, node: ProseMirrorNode) => {
    const annotationId = node.attrs.annotationId;
    if (annotationId) {
      // Add marker at the start of the blockquote content
      state.wrapBlock("> ", null, node, () => {
        // Insert marker before content
        state.text(`[[q:${annotationId}]] `);
        state.renderContent(node);
      });
    } else {
      state.wrapBlock("> ", null, node, () => state.renderContent(node));
    }
  };

  markdownSerializer = new MarkdownSerializer(
    remappedNodes,
    defaultMarkdownSerializer.marks
  );

  postMessage({ type: "ready" });
};

window.VersoNotesInit = initEditor;

window.VersoNotesSetContent = (markdown: string) => {
  if (!editorInstance) {
    return;
  }
  const safeMarkdown = typeof markdown === "string" ? markdown : "";
  isApplyingContent = true;

  try {
    const parser = markdownParser;
    if (!parser) {
      return;
    }
    // Parse the markdown
    const doc = parser.parse(safeMarkdown);

    // Post-process to extract [[q:uuid]] markers and convert to attributes
    const processedDoc = extractQuoteMarkers(doc);

    editorInstance.commands.setContent(processedDoc, { emitUpdate: false });
  } catch (error) {
    editorInstance.commands.setContent("", { emitUpdate: false });
  }
  if (updateTimer) {
    clearTimeout(updateTimer);
  }
  setTimeout(() => {
    isApplyingContent = false;
  }, 0);
};

// Extract [[q:uuid]] markers from blockquotes and convert to annotationId attributes
const extractQuoteMarkers = (doc: ProseMirrorNode): any => {
  if (!editorInstance) return doc;

  const schema = editorInstance.schema;

  const processNode = (node: ProseMirrorNode): ProseMirrorNode => {
    if (node.type.name === "blockquote") {
      // Check if first child paragraph starts with [[q:uuid]]
      let annotationId: string | null = null;
      let newContent: ProseMirrorNode[] = [];

      node.forEach((child, offset, index) => {
        if (index === 0 && child.type.name === "paragraph" && child.content.size > 0) {
          const firstChild = child.content.firstChild;
          if (firstChild && firstChild.isText && firstChild.text) {
            const match = firstChild.text.match(QUOTE_MARKER_REGEX);
            if (match) {
              annotationId = match[1];
              // Remove the marker from the text
              const newText = firstChild.text.replace(QUOTE_MARKER_REGEX, "");
              if (newText) {
                // Create new text node without marker
                const newTextNode = schema.text(newText);
                // Rebuild the paragraph with remaining content
                const remainingContent: ProseMirrorNode[] = [newTextNode];
                child.content.forEach((c, o, i) => {
                  if (i > 0) remainingContent.push(c);
                });
                const newParagraph = schema.nodes.paragraph.create(
                  child.attrs,
                  remainingContent
                );
                newContent.push(newParagraph);
              } else if (child.content.childCount > 1) {
                // Marker was the only text in first node, keep other nodes
                const remainingContent: ProseMirrorNode[] = [];
                child.content.forEach((c, o, i) => {
                  if (i > 0) remainingContent.push(c);
                });
                const newParagraph = schema.nodes.paragraph.create(
                  child.attrs,
                  remainingContent
                );
                newContent.push(newParagraph);
              }
              return;
            }
          }
        }
        // Process child recursively
        newContent.push(processNode(child));
      });

      if (annotationId) {
        // Create new blockquote with annotationId attribute
        return schema.nodes.blockquote.create(
          { annotationId },
          newContent.length > 0 ? newContent : null
        );
      } else if (newContent.length > 0) {
        return schema.nodes.blockquote.create(node.attrs, newContent);
      }
    }

    // For non-blockquote nodes, process children recursively
    if (node.content.size > 0) {
      const newContent: ProseMirrorNode[] = [];
      node.forEach((child) => {
        newContent.push(processNode(child));
      });
      return node.copy(node.content.replaceWith(0, node.content.size, newContent));
    }

    return node;
  };

  return processNode(doc);
};

window.VersoNotesGetMarkdown = () => {
  if (!editorInstance) {
    return "";
  }
  if (!markdownSerializer) {
    return "";
  }
  return markdownSerializer.serialize(editorInstance.state.doc);
};

window.VersoNotesInsertQuote = (quote: string, annotationId: string) => {
  if (!editorInstance) {
    return;
  }

  // Move cursor to end
  editorInstance.commands.focus("end");

  // Insert a paragraph break if not at start
  const { state } = editorInstance;
  if (state.doc.content.size > 2) {
    editorInstance.commands.insertContent("<p></p>");
  }

  // Insert the blockquote with annotationId attribute
  editorInstance.commands.insertContent({
    type: "blockquote",
    attrs: { annotationId },
    content: [
      {
        type: "paragraph",
        content: [{ type: "text", text: quote }],
      },
    ],
  });

  // Add paragraph after for continued typing
  editorInstance.commands.insertContent("<p></p>");

  // Trigger save
  scheduleMarkdownPost();
};
