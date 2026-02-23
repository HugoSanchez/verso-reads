import { Editor } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
import {
  MarkdownParser,
  defaultMarkdownParser,
  defaultMarkdownSerializer,
} from "@tiptap/pm/markdown";

declare global {
  interface Window {
    VersoNotesInit?: () => void;
    VersoNotesSetContent?: (markdown: string) => void;
  }
}

let editorInstance: Editor | null = null;
let isApplyingContent = false;
let updateTimer: ReturnType<typeof setTimeout> | null = null;
let markdownParser: MarkdownParser | null = null;

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
    const markdown = defaultMarkdownSerializer.serialize(editorInstance.state.doc);
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
    },
    onUpdate: () => {
      scheduleMarkdownPost();
    },
  });

  markdownParser = new MarkdownParser(
    editorInstance.schema,
    defaultMarkdownParser.tokenizer,
    defaultMarkdownParser.tokens
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
    const doc = parser.parse(safeMarkdown);
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
