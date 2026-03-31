import { Editor, JSONContent } from "@tiptap/core";
import StarterKit from "@tiptap/starter-kit";
import Placeholder from "@tiptap/extension-placeholder";
import Blockquote from "@tiptap/extension-blockquote";

declare global {
  interface Window {
    VersoNotesInit?: () => void;
    VersoNotesSetContent?: (json: string) => void;
    VersoNotesGetContent?: () => string;
    VersoNotesInsertQuote?: (quote: string, annotationId: string) => void;
    VersoNotesAppendText?: (text: string) => void;
  }
}

// Custom Blockquote extension with annotationId attribute and remove button
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

  addNodeView() {
    return ({ node, HTMLAttributes, getPos }) => {
      const dom = document.createElement("blockquote");
      // Apply attributes
      for (const [key, value] of Object.entries(HTMLAttributes)) {
        if (value != null) dom.setAttribute(key, value);
      }

      const content = document.createElement("div");
      dom.appendChild(content);

      const annotationId = node.attrs.annotationId;
      if (annotationId) {
        const removeBtn = document.createElement("span");
        removeBtn.className = "quote-remove-btn";
        removeBtn.textContent = "×";
        removeBtn.addEventListener("mousedown", (e) => {
          e.preventDefault();
          e.stopPropagation();
          const pos = typeof getPos === "function" ? getPos() : null;
          if (pos != null && editorInstance) {
            // Delete the blockquote node from the editor
            const nodeSize = node.nodeSize;
            editorInstance.commands.deleteRange({
              from: pos,
              to: pos + nodeSize,
            });
            scheduleContentPost();
          }
          // Notify Swift to delete the annotation
          postMessage({ type: "quote-remove", annotationId });
        });
        dom.appendChild(removeBtn);
      }

      return { dom, contentDOM: content };
    };
  },
});

let editorInstance: Editor | null = null;
let isApplyingContent = false;
let updateTimer: ReturnType<typeof setTimeout> | null = null;

const postMessage = (payload: Record<string, unknown>) => {
  if (window.webkit?.messageHandlers?.notes) {
    window.webkit.messageHandlers.notes.postMessage(payload);
  }
};

const scheduleContentPost = () => {
  if (!editorInstance || isApplyingContent) {
    return;
  }
  if (updateTimer) {
    clearTimeout(updateTimer);
  }
  // Short debounce to batch rapid keystrokes, but quick enough to save before sidebar closes
  updateTimer = setTimeout(() => {
    if (!editorInstance || isApplyingContent) {
      return;
    }
    const json = editorInstance.getJSON();
    postMessage({ type: "content", json });
  }, 150);
};

// Find the blockquote node at a given position
const findBlockquoteAt = (
  doc: any,
  pos: number
): { node: any; pos: number } | null => {
  let result: { node: any; pos: number } | null = null;
  doc.nodesBetween(0, doc.content.size, (node: any, nodePos: number) => {
    if (node.type.name === "blockquote") {
      if (nodePos <= pos && pos <= nodePos + node.nodeSize) {
        result = { node, pos: nodePos };
        return false;
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
        blockquote: false,
      }),
      CustomBlockquote,
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
      scheduleContentPost();
    },
  });

  postMessage({ type: "ready" });
};

window.VersoNotesInit = initEditor;

window.VersoNotesSetContent = (json: string) => {
  if (!editorInstance) {
    postMessage({ type: "debug", message: "VersoNotesSetContent: no editor instance" });
    return;
  }
  isApplyingContent = true;

  try {
    if (!json || json === "") {
      postMessage({ type: "debug", message: "VersoNotesSetContent: empty json, clearing" });
      editorInstance.commands.setContent("", { emitUpdate: false });
    } else {
      postMessage({ type: "debug", message: `VersoNotesSetContent: parsing json (length=${json.length})` });
      const content: JSONContent = JSON.parse(json);
      postMessage({ type: "debug", message: `VersoNotesSetContent: parsed OK, setting content (nodes=${content.content?.length ?? 0})` });
      editorInstance.commands.setContent(content, { emitUpdate: false });
      postMessage({ type: "debug", message: "VersoNotesSetContent: setContent done" });
    }
  } catch (error) {
    postMessage({ type: "debug", message: `VersoNotesSetContent ERROR: ${error}` });
    editorInstance.commands.setContent("", { emitUpdate: false });
  }

  if (updateTimer) {
    clearTimeout(updateTimer);
  }
  setTimeout(() => {
    isApplyingContent = false;
  }, 0);
};

window.VersoNotesGetContent = () => {
  if (!editorInstance) {
    return "";
  }
  return JSON.stringify(editorInstance.getJSON());
};

window.VersoNotesInsertQuote = (quote: string, annotationId: string) => {
  if (!editorInstance) {
    return;
  }

  // Build the nodes to append at the document level
  const nodes: JSONContent[] = [];

  const { state } = editorInstance;
  const docSize = state.doc.content.size;

  // Add a spacer paragraph before the blockquote if there's existing content
  if (docSize > 2) {
    nodes.push({ type: "paragraph" });
  }

  nodes.push({
    type: "blockquote",
    attrs: { annotationId },
    content: [
      {
        type: "paragraph",
        content: [{ type: "text", text: quote }],
      },
    ],
  });

  // Empty paragraph after so user can type below
  nodes.push({ type: "paragraph" });

  // Insert all at once at the end of the document to avoid cursor positioning issues
  const endPos = state.doc.content.size;
  editorInstance
    .chain()
    .insertContentAt(endPos, nodes)
    .focus("end")
    .run();

  scheduleContentPost();
};

window.VersoNotesAppendText = (text: string) => {
  if (!editorInstance) {
    return;
  }

  const lines = text.split("\n").filter((l) => l.length > 0);
  const nodes: JSONContent[] = [];

  const { state } = editorInstance;
  const docSize = state.doc.content.size;

  // Add a spacer paragraph before the new content if there's existing content
  if (docSize > 2) {
    nodes.push({ type: "paragraph" });
  }

  for (const line of lines) {
    nodes.push({
      type: "paragraph",
      content: [{ type: "text", text: line }],
    });
  }

  const endPos = state.doc.content.size;
  editorInstance
    .chain()
    .insertContentAt(endPos, nodes)
    .run();

  scheduleContentPost();
};
