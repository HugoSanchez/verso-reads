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
  }
}

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

window.VersoNotesGetMarkdown = () => {
  if (!editorInstance) {
    return "";
  }
  const serializer = markdownSerializer ?? defaultMarkdownSerializer;
  return serializer.serialize(editorInstance.state.doc);
};
