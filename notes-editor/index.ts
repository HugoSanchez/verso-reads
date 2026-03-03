import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
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

// Map to store annotation IDs for blockquotes (keyed by quote text hash)
const blockquoteAnnotations = new Map<string, string>();

// Simple hash for quote text to use as key
const hashQuote = (text: string): string => {
  let hash = 0;
  for (let i = 0; i < text.length; i++) {
    hash = ((hash << 5) - hash) + text.charCodeAt(i);
    hash |= 0;
  }
  return hash.toString(36);
};

// Marker format: [[q:shortId]] at start of blockquote
const QUOTE_MARKER_REGEX = /^\[\[q:([a-f0-9-]+)\]\]\s*/i;

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
    const serializer = markdownSerializer ?? defaultMarkdownSerializer;
    const markdown = serializer.serialize(editorInstance.state.doc);
    postMessage({ type: "markdown", markdown });
  }, 400);
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
      }),
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
        const target = event.target as HTMLElement | null;
        if (!target) return false;

        // Check if click is inside a blockquote
        const blockquote = target.closest("blockquote");
        if (!blockquote) return false;

        // Get the text content and look up annotation ID
        const text = blockquote.textContent || "";
        const hash = hashQuote(text.trim());
        const annotationId = blockquoteAnnotations.get(hash);

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

  // Clear existing annotations map
  blockquoteAnnotations.clear();

  // Pre-process markdown to extract quote markers and store them
  // Blockquotes in markdown start with "> "
  const processedMarkdown = safeMarkdown.replace(
    /^(>\s*)(\[\[q:([a-f0-9-]+)\]\]\s*)/gim,
    (match, prefix, marker, annotationId) => {
      // We'll store the annotation after parsing, keyed by the remaining text
      // For now, just remove the marker from the visible text
      return prefix;
    }
  );

  // Also extract and store annotation IDs by parsing blockquote content
  const blockquoteRegex = /^>\s*\[\[q:([a-f0-9-]+)\]\]\s*(.+?)(?=\n(?!>)|$)/gims;
  let match;
  const tempMarkdown = safeMarkdown;
  while ((match = blockquoteRegex.exec(tempMarkdown)) !== null) {
    const annotationId = match[1];
    const quoteText = match[2].trim();
    const hash = hashQuote(quoteText);
    blockquoteAnnotations.set(hash, annotationId);
  }

  try {
    const parser = markdownParser;
    if (!parser) {
      return;
    }
    const doc = parser.parse(processedMarkdown);
    editorInstance.commands.setContent(doc, { emitUpdate: false });
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

window.VersoNotesGetMarkdown = () => {
  if (!editorInstance) {
    return "";
  }
  const serializer = markdownSerializer ?? defaultMarkdownSerializer;
  let markdown = serializer.serialize(editorInstance.state.doc);

  // Re-insert quote markers into blockquotes
  // Find blockquotes and add markers back if we have an annotation ID for them
  markdown = markdown.replace(/^(>\s*)(.+?)$/gm, (match, prefix, content) => {
    const hash = hashQuote(content.trim());
    const annotationId = blockquoteAnnotations.get(hash);
    if (annotationId) {
      return `${prefix}[[q:${annotationId}]] ${content}`;
    }
    return match;
  });

  return markdown;
};

window.VersoNotesInsertQuote = (quote: string, annotationId: string) => {
  if (!editorInstance) {
    return;
  }

  // Store the annotation mapping
  const hash = hashQuote(quote.trim());
  blockquoteAnnotations.set(hash, annotationId);

  // Move cursor to end and insert blockquote
  editorInstance.commands.focus("end");

  // Insert a paragraph break if not at start
  const { state } = editorInstance;
  if (state.doc.content.size > 2) {
    editorInstance.commands.insertContent("<p></p>");
  }

  // Insert the blockquote
  editorInstance.commands.insertContent({
    type: "blockquote",
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
