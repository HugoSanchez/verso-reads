# Notes Editor Bundle

This folder contains the local, offline-ready web assets for the notes editor.

- `index.html` loads `tiptap.bundle.js` from the app bundle (no network).
- `tiptap.bundle.js` is a bundled TipTap editor built from:
  - `@tiptap/core@2.27.2`
  - `@tiptap/starter-kit@2.27.2`
  - `@tiptap/extension-placeholder@2.27.2`

Rebuild guidance:
- Run `npm install` once.
- Build with `npm run build:notes` (writes `Resources/NotesEditor/tiptap.bundle.js`).
- Keep the entry point and DOM target consistent with `index.html`.
