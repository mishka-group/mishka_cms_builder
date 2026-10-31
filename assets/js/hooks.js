// SPDX-FileCopyrightText: 2026 Mishka Group contributors <https://github.com/mishka-group/mishka_cms_builder/graphs/contributors>
//
// SPDX-License-Identifier: Apache-2.0

// THE VISUAL EDITOR'S HOOKS — the canvas and its frames, the palette, the layers rail, the panels'
// grips and zoom, the keyboard shortcuts, the review composer's `@` list, the SEO tab's variable
// chips and the Assets sheet's dropzone. Every element they attach to is drawn by this package's
// LiveViews; `index.js` hands them to the host's admin bundle.
//
// Everything else in the editor is an ordinary LiveView binding, because the document lives on the
// server. These cover the parts a server genuinely cannot do — pointer geometry, key handling, and
// bridging the canvas iframe. They import no npm package: what they share is beside this file.

import {
  axisOf,
  edgeVelocity,
  formCaption,
  formLanding,
  resolveDrop as resolveDropAt,
  indicatorBox,
} from "./pb_drop.js";
import { mentionAt, withMention } from "./pb_mention.js";
import {
  byRecency,
  favourites,
  noteUse,
  recents,
  shows,
  toggleFavourite,
} from "./pb_prefs.js";

// WHAT A DRAG IS CARRYING, readable while it is still in flight.
//
// A drag crosses between three surfaces — the palette, the layers rail and the canvas iframe — and
// only the surface it STARTED on holds the hook state that says what is moving. Everything else has
// the dataTransfer, whose values are sealed until `drop` but whose TYPE LIST is legible throughout,
// so the type itself is the message: this gesture is moving an existing node, answer it "move".
//
// `text/plain` cannot carry it. Firefox refuses to start a drag with no payload at all, so every
// source already sets it, and a receiving surface reading it could not tell a node from a template
// from a text selection dragged in off the desktop.
const NODE_MIME = "application/x-pb-node";

const TEMPLATE_MIME = "application/x-pb-template";

// THE SERVER'S VERDICT FOR THE DRAG IN FLIGHT, in every window this editor draws in.
//
// `EditorSession.drop_hints/2` answers once per drag which parents will take the node. The reply
// reaches ONE window — the chrome's for a palette card or a layers row, a frame's for a node picked
// up on the canvas — and the pointer is free to travel into any of the others, so it is handed on
// to all of them.
//
// Clearing has to reach exactly as far as setting, and it did not: every source nulled its own
// `window.__pbDropHints` and left the frames holding the previous drag's map. Between the next
// `dragstart` and the next reply landing — one round trip, and longer than that on a slow link — a
// frame would answer from a verdict computed for a different node.
//
// The breakpoint view draws SIX frames of one document, which is why this is a sweep rather than a
// hand-off to the frame the drag started in.
function spreadHints(accepts, field = false) {
  window.__pbDropHints = accepts;
  window.__pbFieldDrag = !!field;

  canvasFrames().forEach((frame) => {
    frame.contentWindow.__pbDropHints = accepts;
    frame.contentWindow.__pbFieldDrag = !!field;
    markFieldDrag(frame.contentDocument, field);
    // A frame the pointer is already over redraws its line from the verdict (`PbCanvas`).
    if (accepts) frame.contentWindow.dispatchEvent(new Event("pb:hints"));
  });
}

// Whether a field is being dragged, on a frame's root element: the canvas outlines its forms while
// it is set.
function markFieldDrag(doc, field) {
  if (!doc || !doc.documentElement) return;
  if (field) doc.documentElement.setAttribute("data-pb-field-drag", "true");
  else doc.documentElement.removeAttribute("data-pb-field-drag");
}

function canvasFrames() {
  return [...document.querySelectorAll('iframe[src*="builder-canvas"]')].filter(
    (frame) => frame.contentWindow,
  );
}

// A drag this window asked `drag_start` about is still in flight, so its `pb:drop-hints` reply is
// still wanted. A reply that lands after the drag ended would mark every frame for a drag nobody is
// making.
let hintsAwaited = false;

// THE END OF A DRAG, in every window this editor draws in, for the same reason the verdict is.
//
// `dragend` fires on the SOURCE. A palette card picked up in this document and released back over
// the palette — or over the rail, or cancelled with Escape — fires it out here and nowhere else, so
// a frame the pointer only passed THROUGH is never told the gesture is over. It opened every empty
// container on the page when the pointer crossed in, and those floors, dashed edges and tints then
// stood for the rest of the session, distorting the geometry the next drop is resolved from.
//
// So the end is broadcast the way the verdict is swept: `PbLayers` is reached through `pb:dragend`
// already (it had this problem first), and `PbCanvas` listens for it inside each frame.
function endDrag() {
  hintsAwaited = false;
  spreadHints(null);
  window.__pbDragNode = null;
  window.dispatchEvent(new Event("pb:dragend"));
  canvasFrames().forEach((frame) => frame.contentWindow.dispatchEvent(new Event("pb:dragend")));
}

// THE DROPZONE IS THE SUBMIT, in the editor's Assets sheet. That sheet is 620px of overlay beside a
// canvas, and a Create button in it is a second step for something the drop already said: put this
// file in this folder. The form is mounted with `submit={false}` so Gervaz draws no button; this is
// what presses it.
//
// IT WATCHES THE INPUT, NOT THE EVENTS. Listening for `change`/`input` looks obvious and is wrong:
// LiveView stages the file in its OWN listener, and a listener that runs first submits a form that
// has no files yet. That is not a race to lose carefully — the picker path always loses it, because
// a capture listener on this container runs before LiveView's on the document. The file then sits
// staged at 0% forever, which is exactly what it did.
//
// `data-phx-active-refs` is LiveView's own record of what is staged, and `data-phx-preflighted-refs`
// of what it has already begun. A ref in the first and not the second is a file waiting to go, and
// that is true however it arrived — dropped or picked. Submitting moves the ref into preflighted,
// so the next mutation finds nothing waiting: no timer, no debounce, no double upload.
const UploadSubmitsItself = {
  mounted() {
    this.watch();
  },
  updated() {
    // A save replaces the input with a fresh one, and the observer is still on the old node.
    this.watch();
  },
  watch() {
    const input = this.el.querySelector('input[type="file"]');
    if (!input || input === this.input) return;

    this.observer?.disconnect();
    this.input = input;
    this.observer = new MutationObserver(() => this.submitWaiting());
    this.observer.observe(input, {
      attributes: true,
      attributeFilter: ["data-phx-active-refs", "data-phx-preflighted-refs"],
    });

    // A file may already be staged — a reconnect, or one left behind by an earlier failure.
    this.submitWaiting();
  },
  submitWaiting() {
    const refs = (name) =>
      (this.input.getAttribute(name) || "").split(",").filter((ref) => ref !== "");

    const started = refs("data-phx-preflighted-refs");
    const waiting = refs("data-phx-active-refs").filter((ref) => !started.includes(ref));

    if (waiting.length > 0) this.input.form?.requestSubmit();
  },
  destroyed() {
    this.observer?.disconnect();
  },
};

// TYPING `@` IN A REVIEW NOTE. The split is deliberate: the browser decides WHEN somebody is being
// named — it is the only thing that knows where the caret is — and the server decides WHO can be
// named, because that is a tenancy question and the browser must not be trusted with the answer.
//
// The hook sits on the textarea itself, so the form rebuilding on `defaults` (which replaces the
// element) remounts it rather than leaving a listener on a textarea that is gone.
const MentionBox = {
  mounted() {
    this.at = null;
    this.open = false;
    this.active = 0;
    this.blurTimer = null;

    this.el.addEventListener("input", () => this.probe());
    this.el.addEventListener("click", () => this.probe());

    // THE KEYBOARD IS HOW AN AUTOCOMPLETE IS USED. Without this, Enter typed a newline and left the
    // half-written `@n` sitting in the note — the list was only ever clickable, which is not what
    // anybody expects from a list that appears while they are typing.
    this.el.addEventListener("keydown", (event) => {
      // WHAT IS ON SCREEN DECIDES, not what this instance remembers. The composer rebuilds itself
      // whenever `defaults` change, which remounts this hook with an empty memory while the list the
      // server rendered is still standing — and a list you can see but cannot arrow through is worse
      // than no list. If the rows are there, recover the caret position and carry on.
      if (this.candidates().length === 0) return;

      if (this.at === null) {
        const found = mentionAt(this.el.value, this.el.selectionStart);
        if (!found) return;
        this.at = found.at;
        this.open = true;
      }

      if (event.key === "ArrowDown" || event.key === "ArrowUp") {
        event.preventDefault();
        this.step(event.key === "ArrowDown" ? 1 : -1);
      } else if (event.key === "Enter" || event.key === "Tab") {
        event.preventDefault();
        this.pick(this.candidates()[this.active]);
      } else if (event.key === "Escape") {
        event.preventDefault();
        this.close();
      }
    });

    this.el.addEventListener("keyup", (event) => {
      if (!["Enter", "Tab", "Escape", "ArrowDown", "ArrowUp"].includes(event.key)) this.probe();
    });

    // The mouse picks through the same path the keyboard does. `mousedown` rather than `click`, with
    // the default prevented, so the caret never leaves the note — a click that blurs first is a
    // click that closes the list it was aimed at.
    this.onMouseDown = (event) => {
      const option = event.target.closest("#pb-mention-list [data-handle]");
      if (!option) return;
      event.preventDefault();
      this.pick(option);
    };

    document.addEventListener("mousedown", this.onMouseDown);
    // A blur closes it, but not before a click on the list has landed — the click IS a blur. The
    // timer is stored and cancelled on focus so a patch that relocates the textarea cannot close the
    // list behind the author's back: LiveView hands focus straight back, and only a real click away
    // leaves it gone.
    this.el.addEventListener("blur", () => {
      this.blurTimer = setTimeout(() => this.close(), 200);
    });
    this.el.addEventListener("focus", () => clearTimeout(this.blurTimer));

  },

  candidates() {
    return Array.from(document.querySelectorAll("#pb-mention-list [data-handle]"));
  },

  // Which row Enter would take, painted where the reader is looking. Painting and remembering are
  // one step on purpose: they drifted apart when only one of them ran, and a highlight that lies
  // about what Enter will do is worse than no highlight.
  step(by) {
    const options = this.candidates();
    if (options.length === 0) return;

    this.active = (this.active + by + options.length) % options.length;
    this.paint(options);
    options[this.active].scrollIntoView({ block: "nearest" });
  },

  paint(options) {
    options.forEach((option, index) =>
      option.setAttribute("data-active", index === this.active ? "true" : "false"),
    );
  },

  pick(option) {
    if (!option) return;
    this.insert(option.dataset.handle);
    this.close();
  },

  probe() {
    const found = mentionAt(this.el.value, this.el.selectionStart);

    if (!found) return this.close();

    this.at = found.at;
    this.open = true;

    // A NEW WORD IS A NEW LIST. The server re-renders it with the first row highlighted, so the
    // hook has to agree — and repaint, because the rows on screen may be the previous answer still.
    this.active = 0;
    this.paint(this.candidates());

    // One search per pause rather than one per keystroke: the list is a query, and holding a key
    // down should not be a query per character.
    clearTimeout(this.timer);
    this.timer = setTimeout(() => this.pushEvent("mention_search", { q: found.query }), 120);
  },

  // The one place the list is finished with — writing the name does not close it, or `pick` would
  // have nothing left to tell the server and the list would sit there over the note it just wrote.
  close() {
    clearTimeout(this.timer);
    if (!this.open) return;
    this.open = false;
    this.at = null;
    this.pushEvent("mention_close", {});
  },

  // Only the browser knows where the caret is, so only the browser can put the name where it goes.
  insert(handle) {
    if (this.at === null) return;

    const written = withMention(this.el.value, this.at, this.el.selectionStart, handle);

    this.el.value = written.value;
    this.el.setSelectionRange(written.caret, written.caret);
    this.el.focus();
  },

  destroyed() {
    clearTimeout(this.timer);
    clearTimeout(this.blurTimer);
    document.removeEventListener("mousedown", this.onMouseDown);
  },
};

// Copy-to-clipboard for the Studio's generated export. The text is on the button as a data
// attribute rather than fetched, because the server already rendered exactly what is on screen —
// copying anything else would hand over something the reader never saw.
const PbCopy = {
  mounted() {
    this.onClick = async () => {
      const text = this.el.dataset.copy || "";
      try {
        await navigator.clipboard.writeText(text);
        this.flash("Copied");
      } catch {
        this.flash("Press ⌘C");
      }
    };

    this.flash = (label) => {
      const original = this.el.textContent;
      this.el.textContent = label;
      clearTimeout(this.timer);
      this.timer = setTimeout(() => (this.el.textContent = original), 1400);
    };

    this.el.addEventListener("click", this.onClick);
  },
  destroyed() {
    clearTimeout(this.timer);
    this.el.removeEventListener("click", this.onClick);
  },
};

// A horizontal strip you can pan by dragging it, for the palette's category chips. The row is
// deliberately scrollbar-less — a scrollbar under a row of chips eats a line of pixels and reads as
// a defect — so without this the overflow would be reachable by wheel alone.
//
// A drag that never really moved is left alone so the chip under the pointer still receives its
// click; only past a few pixels does this take over and suppress it.
const PbDragScroll = {
  mounted() {
    this.onDown = (event) => {
      if (event.button !== 0) return;
      this.start = { x: event.clientX, left: this.el.scrollLeft };
      this.moved = false;
      this.el.style.cursor = "grabbing";
    };

    this.onMove = (event) => {
      if (!this.start) return;
      const dx = event.clientX - this.start.x;
      if (Math.abs(dx) <= 3) return;

      // Capture is taken only once the gesture has become a DRAG. Taking it on pointerdown made
      // every pointerup land on this row instead of the chip under the cursor, and the browser
      // fires `click` on the nearest common ancestor of the two — so the chip never got one and the
      // category filter, the frame row and the assistant's starter chips all looked dead.
      if (!this.moved) {
        this.moved = true;
        this.el.setPointerCapture?.(event.pointerId);
      }

      this.el.scrollLeft = this.start.left - dx;
    };

    this.onUp = (event) => {
      if (!this.start) return;
      this.start = null;
      this.el.style.cursor = "";
      if (this.moved) this.el.releasePointerCapture?.(event.pointerId);
    };

    this.onClick = (event) => {
      if (!this.moved) return;
      event.preventDefault();
      event.stopPropagation();
      this.moved = false;
    };

    this.el.addEventListener("pointerdown", this.onDown);
    this.el.addEventListener("pointermove", this.onMove);
    this.el.addEventListener("pointerup", this.onUp);
    this.el.addEventListener("pointercancel", this.onUp);
    this.el.addEventListener("click", this.onClick, true);
  },
  destroyed() {
    this.el.removeEventListener("pointerdown", this.onDown);
    this.el.removeEventListener("pointermove", this.onMove);
    this.el.removeEventListener("pointerup", this.onUp);
    this.el.removeEventListener("pointercancel", this.onUp);
    this.el.removeEventListener("click", this.onClick, true);
  },
};

// A 6px column/row grip. Pointer capture means the drag survives the cursor leaving the element —
// including the canvas iframe, which would otherwise swallow the rest of the gesture.
//
// The size belongs to the BROWSER while the pointer is down. It used to be pushed on every
// pointermove, and a mouse reports sixty to a hundred and twenty times a second: each report was a
// socket round trip that re-rendered the panel, so the divider trailed the cursor and then kept
// sliding for seconds after the mouse came up, draining a queue nobody could stop. Measured on this
// page: sixty moves in one drag, sixty messages, five seconds to settle.
//
// So the drag paints locally, one style write per animation frame, and the server is told once —
// when the gesture ends — because the assign is what any later re-render, reconnect or reload
// renders the panel from. `data-min`/`data-max` come from the same bounds the LiveView clamps to,
// so the local drag stops exactly where the server would have stopped it and nothing snaps back.
const PbGrip = {
  mounted() {
    this.panel = this.el.dataset.panel;
    this.min = Number(this.el.dataset.min) || -Infinity;
    this.max = Number(this.el.dataset.max) || Infinity;
    this.prop = this.el.dataset.var;
    this.onDown = (event) => this.begin(event);
    this.el.addEventListener("pointerdown", this.onDown);
  },

  // A hook whose element is gone cannot talk to the server — collapsing the panel mid-drag removes
  // this grip — so teardown only unbinds. The size the drag reached is lost with the panel it sized,
  // which is the same thing the reader just did by collapsing it.
  destroyed() {
    this.el.removeEventListener("pointerdown", this.onDown);
    this.finish(false);
  },

  begin(event) {
    const target = this.target();
    if (!target || this.dragging) return;

    event.preventDefault();
    this.el.setPointerCapture(event.pointerId);

    this.dragging = target;
    this.frame = null;
    this.value = null;
    this.origin = {
      x: event.clientX,
      y: event.clientY,
      size: this.vertical() ? target.offsetHeight : target.offsetWidth,
    };

    this.onMove = (ev) => this.track(ev);
    this.onEnd = () => this.finish();

    this.el.addEventListener("pointermove", this.onMove);
    this.el.addEventListener("pointerup", this.onEnd);
    this.el.addEventListener("pointercancel", this.onEnd);
    // Alt-tab, a system gesture or the element being patched away all end the drag without a
    // pointerup. Without this the listeners would outlive the gesture and the size would never
    // reach the server.
    this.el.addEventListener("lostpointercapture", this.onEnd);
  },

  track(ev) {
    this.value = this.clamp(this.origin.size + this.delta(ev));

    // One write per frame. A pointer reports faster than the screen redraws, and a style write per
    // report is work no one can see.
    if (this.frame) return;

    this.frame = requestAnimationFrame(() => {
      this.frame = null;
      this.paint();
    });
  },

  finish(tell = true) {
    if (!this.dragging) return;

    this.el.removeEventListener("pointermove", this.onMove);
    this.el.removeEventListener("pointerup", this.onEnd);
    this.el.removeEventListener("pointercancel", this.onEnd);
    this.el.removeEventListener("lostpointercapture", this.onEnd);

    if (this.frame) cancelAnimationFrame(this.frame);
    this.frame = null;
    this.paint();

    // The one message of the whole gesture. `value` is null when the pointer went down and came up
    // without moving — a click on the divider is not a resize.
    if (tell && this.value !== null) {
      this.pushEvent("resize", { panel: this.panel, value: this.value });
    }

    this.dragging = null;
    this.value = null;
  },

  // Written to `<html>`, not to the panel. The panel's own `style` is re-emitted by the server on
  // every render of the editor — these panels are called with a bare `{assigns}` splat, which turns
  // LiveView's change tracking off for them — so anything written on the element itself is stamped
  // back to the last value the server knows the moment an autosave tick or another editor's edit
  // lands mid-gesture. The custom property is outside the LiveView, and the element's style reads
  // `width:var(--pb-left-w, 272px)`: the server's number stays the fallback, the drag out-specifies
  // it, and the patch it keeps rewriting says exactly the same thing either way.
  paint() {
    if (!this.dragging || this.value === null || !this.prop) return;
    document.documentElement.style.setProperty(this.prop, `${this.value}px`);
  },

  // The drawer grows UPWARDS and the right panel leftwards, so both read the cursor backwards.
  delta(ev) {
    if (this.panel === "left") return ev.clientX - this.origin.x;
    if (this.panel === "right") return this.origin.x - ev.clientX;
    return this.origin.y - ev.clientY;
  },

  clamp(value) {
    return Math.round(Math.min(this.max, Math.max(this.min, value)));
  },

  vertical() {
    return this.panel === "drawer";
  },

  target() {
    if (this.panel === "left") return document.getElementById("pb-left");
    if (this.panel === "right") return document.getElementById("pb-right");
    return document.querySelector('[data-role="pb-drawer"]');
  },
};

// THE CANVAS ZOOM, PAINTED IN THE BROWSER AND TOLD TO THE SERVER ONCE THE CLICKING STOPS.
//
// Mount `PbZoom` on every element whose markup shows a zoom, and give it:
//   - `data-zoom`: the zooms it shows, space-separated ("single", "frame")
//   - `data-<zoom>-zoom`: the server's value of each, in percent
//   - `data-zoom-root` when it carries `--pb-<zoom>-zoom` (the value / 100) for the frames under it
//   - `data-min`, `data-max` and `data-event` when it holds the buttons of one zoom: a
//     `data-zoom-step` button adds its step, a `data-zoom-reset` button sets its own value
// Put `data-zoom-label="<zoom>"` on any element whose whole text is the value and a "%".
//
// A click repaints every one of those for its zoom at once and pushes `data-event` with `{ value }`
// a single time, `ZOOM_SETTLE_MS` after the last click. A patch that renders the value the server
// already had is painted over with the browser's; one that renders a value the browser never sent
// is the server changing the zoom itself, and the browser takes it.
const ZOOM_SETTLE_MS = 300;

const zoomKinds = (el) => (el.dataset.zoom || "").split(/\s+/).filter(Boolean);

// The server's value of `kind` as this element renders it, or null when it renders none.
const renderedZoom = (el, kind) => {
  const raw = el.getAttribute(`data-${kind}-zoom`);
  const value = raw === null || raw === "" ? NaN : Number(raw);

  return Number.isInteger(value) ? value : null;
};

const PB_ZOOM = {
  hooks: new Set(),
  zooms: {},

  // `value` is on screen, `server` is the last value a patch rendered, `sent` the values pushed and
  // not yet rendered back, oldest first.
  zoom(kind) {
    if (!this.zooms[kind]) {
      this.zooms[kind] = {
        value: null,
        server: null,
        sent: [],
        timer: null,
        event: null,
        from: null,
      };
    }

    return this.zooms[kind];
  },

  receive(kind, rendered) {
    const zoom = this.zoom(kind);
    if (rendered === null || rendered === zoom.server) return;

    zoom.server = rendered;

    const ours = zoom.sent.indexOf(rendered);
    if (ours !== -1) {
      zoom.sent.splice(0, ours + 1);
      return;
    }

    clearTimeout(zoom.timer);
    zoom.timer = null;
    zoom.sent = [];
    zoom.value = rendered;
  },

  set(kind, value, from) {
    const zoom = this.zoom(kind);

    zoom.value = value;
    zoom.event = from.el.dataset.event;
    zoom.from = from;
    this.paint(kind);

    clearTimeout(zoom.timer);
    zoom.timer = setTimeout(() => this.flush(kind), ZOOM_SETTLE_MS);
  },

  // Pushes the settled value from the hook that was clicked, or from any hook still mounted once
  // that one is gone. A value the server already has, or is about to, is not pushed again.
  flush(kind) {
    const zoom = this.zoom(kind);
    zoom.timer = null;

    const coming = zoom.sent.length ? zoom.sent[zoom.sent.length - 1] : zoom.server;
    if (zoom.value === coming || !zoom.event) return;

    const hook = this.hooks.has(zoom.from) ? zoom.from : this.hooks.values().next().value;
    if (!hook) return;

    zoom.sent.push(zoom.value);
    hook.pushEvent(zoom.event, { value: zoom.value });
  },

  // Writes only what differs, so an element already showing the server's value keeps the exact
  // markup the server rendered.
  paint(kind) {
    const value = this.zoom(kind).value;
    if (value === null) return;

    const prop = `--pb-${kind}-zoom`;
    const scale = value / 100;
    const text = `${value}%`;

    for (const root of document.querySelectorAll("[data-zoom-root]")) {
      if (!zoomKinds(root).includes(kind)) continue;
      if (Number(root.style.getPropertyValue(prop)) !== scale) {
        root.style.setProperty(prop, String(scale));
      }
    }

    for (const label of document.querySelectorAll(`[data-zoom-label="${kind}"]`)) {
      if (label.textContent !== text) label.textContent = text;
    }

    for (const group of document.querySelectorAll("[data-zoom][data-event]")) {
      if (group.dataset.zoom !== kind) continue;

      const min = Number(group.dataset.min);
      const max = Number(group.dataset.max);

      for (const button of group.querySelectorAll("[data-zoom-step]")) {
        const off = Number(button.dataset.zoomStep) < 0 ? value <= min : value >= max;
        if (button.disabled !== off) button.disabled = off;
      }
    }
  },

  // The last hook to go takes the state with it, so the next editor starts from its own render.
  release(hook) {
    this.hooks.delete(hook);
    if (this.hooks.size) return;

    for (const zoom of Object.values(this.zooms)) clearTimeout(zoom.timer);
    this.zooms = {};
  },
};

const PbZoom = {
  mounted() {
    PB_ZOOM.hooks.add(this);
    this.onClick = (event) => this.press(event);
    this.el.addEventListener("click", this.onClick);
    this.sync();
  },
  updated() {
    this.sync();
  },
  destroyed() {
    this.el.removeEventListener("click", this.onClick);
    PB_ZOOM.release(this);
  },

  sync() {
    for (const kind of zoomKinds(this.el)) {
      PB_ZOOM.receive(kind, renderedZoom(this.el, kind));
      PB_ZOOM.paint(kind);
    }
  },

  press(event) {
    const button =
      event.target.closest && event.target.closest("[data-zoom-step], [data-zoom-reset]");
    if (!button || !this.el.contains(button) || button.disabled) return;

    const [kind] = zoomKinds(this.el);
    const current = PB_ZOOM.zoom(kind).value;
    const wanted = button.hasAttribute("data-zoom-reset")
      ? Number(button.dataset.zoomReset)
      : current + Number(button.dataset.zoomStep);
    const min = Number(this.el.dataset.min);
    const max = Number(this.el.dataset.max);
    const next = Math.min(max, Math.max(min, wanted));

    if (!Number.isInteger(next) || next === current) return;

    PB_ZOOM.set(kind, next, this);
  },
};

// THE EDITOR'S KEYBOARD, in one place because two hooks read it — `PbShortcuts` on the chrome and
// `PbCanvas` inside the frame, which cannot see the chrome's listener at all.
//
// MATCHED ON THE PHYSICAL KEY, NOT ON THE CHARACTER. `event.key` is what the LAYOUT produced: on a
// Persian keyboard ⌘Z arrives as `ز`, on a Russian one as `я`, on Dvorak as `;`. Every shortcut here
// compared against `"z"` and friends, so on any non-Latin layout the whole editor keyboard was dead
// — undo, save, copy, paste, duplicate, the command palette, all of it — with nothing on screen to
// say why. Reported as "I pressed Ctrl+Z and the second block didn't come back"; reverting from the
// history sheet worked, because that is a click.
//
// `event.code` names the key by WHERE IT IS — `KeyZ` is the same key on every layout — so it is the
// answer for the letters. `event.key` stays as the fallback for everything `code` cannot spell the
// same way everywhere, and for browsers that do not send one.
export const PB_KEYS = (event) => {
  const code = event.code || "";

  return {
    letter: /^Key[A-Z]$/.test(code) ? code.slice(3).toLowerCase() : null,
    key: (event.key || "").toLowerCase(),
    code,
  };
};

export const PB_SHORTCUTS = (event) => {
  const mod = event.metaKey || event.ctrlKey;
  const { letter, key, code } = PB_KEYS(event);

  // The physical key when the browser named one, the character otherwise.
  const is = (want) => (letter ? letter === want : key === want);

  if (mod && is("z")) return event.shiftKey ? "redo" : "undo";
  if (mod && is("s")) return "save";
  if (mod && is("c")) return "copy";
  if (mod && is("x")) return "cut";
  if (mod && is("v")) return "paste";
  if (mod && is("d")) return "duplicate";
  // ⇧⌘H, Figma's and Sketch's hide and show; ⌘H alone is the system's on a Mac.
  if (mod && event.shiftKey && is("h")) return "visibility";
  if (mod && is("k")) return "command";
  if (mod && (code === "Slash" || key === "/")) return "code";
  if (mod && is("p")) return "preview";
  if (code === "Escape" || key === "escape") return "escape";
  if (code === "Delete" || code === "Backspace" || key === "delete" || key === "backspace") {
    return "delete";
  }
  if (event.shiftKey && (code === "Digit1" || key === "!")) return "fit";
  return null;
};

// Typing in a field must stay typing.
const PB_EDITABLE = (target) =>
  target &&
  (target.isContentEditable ||
    ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName));

// A field that holds typed text: inline words on the canvas, the Code window's CodeMirror, a text
// input, a textarea. A `<select>` or a checkbox holds none.
const PB_TEXT_INPUTS = ["text", "search", "url", "tel", "email", "password", "number"];

const PB_TYPED = (target) =>
  target.isContentEditable ||
  target.tagName === "TEXTAREA" ||
  (target.tagName === "INPUT" && PB_TEXT_INPUTS.includes(target.type));

// Whether a field keeps this key for itself, so the editor neither prevents nor sends it.
//
// UNDO AND REDO IN TYPED TEXT ARE THE FIELD'S OWN. The words being typed are not in the document
// yet: inline text is written by `set_text` on blur, so ⌘Z sent to the server undid the structural
// change before them while they stayed on screen. Left to the field, it is the browser's undo, or
// CodeMirror's own history in the Code window. With the focus anywhere else, a `<select>` included,
// ⌘Z still undoes the page.
const PB_FIELD_KEEPS = (event, shortcut) => {
  if (!PB_EDITABLE(event.target)) return false;
  if (shortcut !== "undo" && shortcut !== "redo") return true;
  return PB_TYPED(event.target);
};

// A MODAL THAT CLOSES ITSELF OWNS ESCAPE. Each one marked `data-pb-modal` binds
// `phx-window-keydown` on escape, the one binding that also hears the key inside CodeMirror, where
// this hook stands back as it does for any field. Pushed from here as well, one press made two
// pushes, and this hook's locks `#pb-root`, every modal's ancestor: LiveView then patched the
// modal's removal into a detached copy of the locked tree, so the dialog faded out and its
// full-screen backdrop stayed, taking every click until a reload.
const PB_MODAL_OPEN = () => document.querySelector("[data-pb-modal]") !== null;

// ⌘A or Ctrl+A, by the physical key like every other shortcut here, and with nothing else held.
const selectsAll = (event) => {
  const { letter, key } = PB_KEYS(event);

  return (
    (event.metaKey || event.ctrlKey) &&
    !event.shiftKey &&
    !event.altKey &&
    (letter ? letter === "a" : key === "a")
  );
};

function selectContents(node) {
  const doc = node.ownerDocument;
  const range = doc.createRange();
  range.selectNodeContents(node);

  const selection = doc.getSelection();
  selection.removeAllRanges();
  selection.addRange(range);
}

// THE ENDS OF THE WORDS BEING TYPED, which is what "the end of the document" means inside them: ⌘↓ and
// ⌘↑ on a Mac, ⌘ or Ctrl with End and Home anywhere, Shift to carry the selection along. The browser
// does not always answer them — on a Mac it reaches for the system's key bindings, which a key event
// from automation or an embedded browser never passes through, and Chrome's own table there holds
// only the plain End, the end of the visual line — so an e2e run's ⌘End did nothing and the words
// it typed next landed where the double click had put the caret, inside "Build". Answered here they
// work the same everywhere, and cannot reach past the words into the page around them.
const runEdge = (event) => {
  const mod = event.metaKey || event.ctrlKey;

  if (mod && !event.altKey && event.key === "End") return "end";
  if (mod && !event.altKey && event.key === "Home") return "start";

  // Ctrl+↓ and Ctrl+↑ are a paragraph's on Windows and Linux, and the system's on a Mac.
  if (!event.metaKey || event.ctrlKey || event.altKey) return null;
  if (event.key === "ArrowDown") return "end";
  if (event.key === "ArrowUp") return "start";

  return null;
};

function caretToEdge(node, edge, extend, shown) {
  const doc = node.ownerDocument;
  const selection = doc.getSelection();
  const [container, offset] = edgeOf(node, edge, shown);

  if (extend && selection.rangeCount && node.contains(selection.anchorNode)) {
    return selection.extend(container, offset);
  }

  const range = doc.createRange();
  range.setStart(container, offset);
  range.collapse(true);
  selection.removeAllRanges();
  selection.addRange(range);
}

// THE FIRST AND LAST WORD, not the template's indentation around them. A run written on its own line
// of the source starts with a newline and ends with the next line's indentation; on screen they are
// nothing, but a caret put after them made "!" typed at the end arrive as "today !". Where the
// element shows its line breaks (`shown`) they are words like any other, and the ends are the run's
// own.
function edgeOf(node, edge, shown) {
  const walker = node.ownerDocument.createTreeWalker(node, NodeFilter.SHOW_TEXT);
  const texts = [];
  while (walker.nextNode()) texts.push(walker.currentNode);

  if (edge === "end") {
    for (const text of texts.reverse()) {
      const at = shown ? text.data.length : text.data.replace(/[ \t\n\r\f]+$/, "").length;
      if (at > 0) return [text, at];
    }

    return [node, node.childNodes.length];
  }

  for (const text of texts) {
    const at = shown ? 0 : text.data.search(/[^ \t\n\r\f]/);
    if (at >= 0 && text.data.length > 0) return [text, at];
  }

  return [node, 0];
}

// WHERE THE CARET GOES WHEN WORDS OPEN FOR EDITING. `focus()` on an editing host puts it at the
// start, so the first thing typed went in front of the old words — "Mishka Studio" typed over
// "Northwind" came out "Mishka StudioNorthwind". A word the double click already selected inside
// the node is kept, as every text field does; otherwise the caret goes where the pointer was, and
// to the end when the browser cannot say where that is.
//
// `aim` is where the pointer was, asked BEFORE the words were opened (`pointRange`): once the run is
// `contenteditable`, Chrome answers every point inside the canvas's unselectable words with their
// very first position, so the caret opened in front of "Build" whichever word was double-clicked,
// and what the author typed went in ahead of the heading.
function caretAt(node, aim) {
  const doc = node.ownerDocument;
  const selection = doc.getSelection();
  if (!selection) return;

  const current = selection.rangeCount ? selection.getRangeAt(0) : null;
  if (current && !current.collapsed && node.contains(current.commonAncestorContainer)) return;

  const range = aim || doc.createRange();
  if (!node.contains(range.startContainer)) {
    range.selectNodeContents(node);
    range.collapse(false);
  }

  selection.removeAllRanges();
  selection.addRange(range);
}

// WHETHER THE LINE BREAKS IN THESE WORDS ARE ON SCREEN. `textContent` carries the newline and the
// indentation of the template the words were written in; on an element that collapses spacing they
// are one space, and the server stores them as one (`CanvasLive`'s `unwrapped/2`). Only the browser
// knows which an element is — a `<pre>`, a `whitespace-pre-line` class, a kit's own stylesheet — so
// the hook reads it off the element and says so with the words.
//
// Read BEFORE the words open: Chrome draws a `plaintext-only` editing host `white-space: pre-wrap`,
// so asked while they are open, every element answers that it shows its line breaks.
export function keepsBreaks(node) {
  const view = node.ownerDocument.defaultView;
  const style = view && view.getComputedStyle(node);
  if (!style) return false;

  // Either spelling: the longhand where the browser has it, the shorthand everywhere.
  return (
    ["preserve", "preserve-breaks", "break-spaces"].includes(style.whiteSpaceCollapse) ||
    ["pre", "pre-wrap", "pre-line", "break-spaces"].includes(style.whiteSpace)
  );
}

function pointRange(doc, event) {
  if (!event || typeof event.clientX !== "number") return null;

  if (doc.caretPositionFromPoint) {
    const position = doc.caretPositionFromPoint(event.clientX, event.clientY);
    if (!position) return null;

    const range = doc.createRange();
    range.setStart(position.offsetNode, position.offset);
    range.collapse(true);
    return range;
  }

  return doc.caretRangeFromPoint ? doc.caretRangeFromPoint(event.clientX, event.clientY) : null;
}

const PbShortcuts = {
  mounted() {
    // Reload the CANVAS, not the editor: the frame's own location, so the panels, the drawer and the
    // scroll position all survive. `src = src` is a no-op in some browsers when the URL is unchanged.
    this.handleEvent("pb:reload-canvas", () => {
      this.el
        .querySelectorAll('iframe[src*="builder-canvas"]')
        .forEach((frame) => frame.contentWindow?.location.reload());
    });

    // THE SERVER'S VERDICT, AND WHERE IT HAS TO END UP. `EditorSession.drop_hints/2` answers, once
    // per drag, which parents will take the node — and both `BuilderLive` and `CanvasLive` push it.
    // Nothing listened for either. Every assignment in this file set `__pbDropHints` to `null`, so
    // the whole gesture ran on the optimistic fallback: the blue line offered parents the server was
    // about to refuse, the drop was then relocated somewhere else, and the layers rail offered
    // "inside" for a `<span>` a `<section>` cannot enter.
    //
    // A palette card and a layers row begin their drag in THIS document, so this is the copy the
    // rail reads. The pointer, though, is going to arrive in a FRAME that never saw that dragstart
    // and will never ask — so the answer is handed on to each of them as well.
    this.handleEvent(
      "pb:drop-hints",
      ({ accepts, field }) => hintsAwaited && spreadHints(accepts, field),
    );

    this.onKey = (event) => {
      // A HELD key auto-repeats about thirty times a second, and every one of these shortcuts is a
      // document mutation: leaning on ⌘Z walks the whole undo stack off the end, on Delete removes a
      // node per repeat, on ⌘S writes to the database per repeat. A shortcut is a press, not a rate.
      if (event.repeat) return;

      const shortcut = PB_SHORTCUTS(event);
      if (!shortcut) return;
      if (PB_FIELD_KEEPS(event, shortcut)) return;
      if (shortcut === "escape" && PB_MODAL_OPEN()) return;

      event.preventDefault();
      // The selection this chrome last drew — the highlighted layers row, the Inspector — is the one
      // the author is looking at when the key is pressed out here. See the canvas's `onKey`.
      this.pushEvent("shortcut", { key: shortcut, node_id: this.el.dataset.selection || null });
    };

    // The canvas cannot push to this LiveView, so it posts here instead.
    this.onMessage = (event) => {
      if (event.source === window || !event.data || event.data.pb !== true) return;
      if (event.data.kind === "shortcut") {
        this.pushEvent("shortcut", {
          key: event.data.key,
          node_id: event.data.node_id || null,
          typing: event.data.typing === true,
        });
      }
      if (event.data.kind === "error") this.pushEvent("flash_error", { message: event.data.message });
      if (event.data.kind === "info") this.pushEvent("flash_info", { message: event.data.message });
      if (event.data.kind === "rail") this.pushEvent("open_rail", { action: event.data.action });

      // A DRAG THAT BEGAN IN A FRAME, reported here because the layers rail is in THIS document and
      // is where the pointer is heading. `drag` carries which node, so the rail stops offering the
      // dragged row as a place to drop it; `hints` carries the server's verdict, so the rail stops
      // guessing; `dragend` puts both back, since the `dragend` itself fires inside the frame and no
      // listener out here would ever see it.
      if (event.data.kind === "drag") {
        window.__pbDragNode = event.data.node_id;
        spreadHints(null);
      }

      // A MENU IN THE CHROME CANNOT SEE A CLICK IN THE CANVAS. `phx-click-away` walks THIS document
      // for open menus and compares them against where the press started — and a press inside the
      // frame is an event in another document that never reaches it. So the "..." menu, the preview
      // and stage pickers and every other dropdown stayed open while you clicked the page behind
      // them, and only a click on the chrome itself would shut them.
      //
      // Replayed as a real press on the BODY, which is in this document, is visible, and is outside
      // every menu — so LiveView answers it exactly as it answers a click on empty chrome, and each
      // of the 21 click-away bindings works without being named here.
      //
      // NOT ON THE FRAME ELEMENT. After click-away LiveView also runs the nearest `phx-click` above
      // the target, and the frame sits inside `#pb-canvas-scroll`, whose `phx-click` is `place`: every
      // press in the canvas sent it, so an armed palette component landed at the top of the page
      // before the canvas could place it where it was clicked. Nothing binds a click above the body.
      if (event.data.kind === "dismiss") {
        document.body.dispatchEvent(new MouseEvent("mousedown", { bubbles: true }));
        document.body.dispatchEvent(new MouseEvent("click", { bubbles: true }));
      }

      if (event.data.kind === "hints") spreadHints(event.data.accepts, event.data.field);

      if (event.data.kind === "dragend") endDrag();
    };

    // EVERY DRAG THAT BEGINS IN THE CHROME ENDS HERE, and nowhere else: `dragend` fires on the
    // source, so a palette card or a layers row released over any surface reports to this document
    // alone. One listener on the way out is what keeps the frames from being told by each source in
    // turn — and from being forgotten by the next source that is added.
    this.onDragEnd = () => endDrag();

    window.addEventListener("keydown", this.onKey);
    window.addEventListener("message", this.onMessage);
    window.addEventListener("dragend", this.onDragEnd, true);
  },
  destroyed() {
    window.removeEventListener("keydown", this.onKey);
    window.removeEventListener("message", this.onMessage);
    window.removeEventListener("dragend", this.onDragEnd, true);
  },
};

const PbTheme = {
  mounted() {
    this.onClick = () => {
      const root = document.documentElement;
      const dark = root.getAttribute("data-theme") === "dark";
      const next = dark ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try {
        localStorage.setItem("phx:theme", next);
      } catch (_denied) {
        // Private browsing refuses localStorage; the theme still applies for this page.
      }
      // The prototype paints the page behind the editor too, so a short page has no light band.
      document.body.style.background = next === "dark" ? "#100f16" : "#f6f5f2";
    };
    this.el.addEventListener("click", this.onClick);
  },
  destroyed() {
    this.el.removeEventListener("click", this.onClick);
  },
};

// PUBLISH MODE WRITES NOTHING, which is the whole point of it — a refresh brings the original back.
// The cost is that leaving is indistinguishable from discarding, so this is the one place the editor
// asks before losing work.
//
// Two exits, two mechanisms. Closing the tab, reloading and typing a URL are `beforeunload`, where
// the browser owns the wording and all we can do is object. A click on a link to another page of
// this app is caught here, on the way down, and handed to the server, which can offer to keep the
// work as a draft rather than only asking twice. That is both kinds of link the editor draws: a
// live `<.link navigate>` to another of the editor's own pages, and a plain `href` to the rest of
// the admin, which is a page load because the editor is a live_session of its own and LiveView
// refuses a live navigation out of it. `leavingTo` says which clicks leave.
//
// When the server lets the author go it redirects or navigates, and LiveView destroys this hook
// before the page unloads, so the browser does not ask a second time.
const PbLeaveGuard = {
  mounted() {
    this.armed = () => this.el.dataset.armed === "true";

    this.warn = (event) => {
      if (!this.armed()) return;
      event.preventDefault();
      event.returnValue = "";
    };

    this.intercept = (event) => {
      if (!this.armed() || event.defaultPrevented || event.button > 0) return;
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;

      const link = event.target.closest && event.target.closest("a[href]");
      const to = link && leavingTo(link);
      if (!to) return;

      event.preventDefault();
      event.stopPropagation();
      this.pushEvent("leaving", { to });
    };

    window.addEventListener("beforeunload", this.warn);
    document.addEventListener("click", this.intercept, true);
  },
  destroyed() {
    window.removeEventListener("beforeunload", this.warn);
    document.removeEventListener("click", this.intercept, true);
  },
};

// WHERE A CLICK ON `link` LEAVES THIS PAGE FOR, as a path of this app, or null when it does not
// leave it. Left alone: a `patch` link, which changes the URL of the editor you are already in; a
// jump to a `#fragment` of this same page; a link that opens elsewhere — a new tab or window, a
// download; and one to another origin, `mailto:` or `javascript:`, which the server would refuse
// as a destination anyway (`beforeunload` still objects if it does unload the page).
function leavingTo(link) {
  if (link.getAttribute("data-phx-link") === "patch") return null;
  if (link.hasAttribute("download")) return null;

  const target = (link.getAttribute("target") || "").toLowerCase();
  if (target && !["_self", "_top", "_parent"].includes(target)) return null;

  let url;
  try {
    url = new URL(link.getAttribute("href"), window.location.href);
  } catch (_invalid) {
    return null;
  }

  if (url.origin !== window.location.origin) return null;

  const [page, fragment] = url.href.split("#");
  if (fragment !== undefined && page === window.location.href.split("#")[0]) return null;

  return url.pathname + url.search + url.hash;
}

// WHEN THE FRAME HAS ACTUALLY REPAINTED THE NEW DOCUMENT. Opening a draft replaces the tree in the
// session and the frames re-render from a broadcast — no navigation, so `FrameLoader`'s `load` never
// fires again and its spinner can never come back. The editor raises the busy overlay when it asks
// for the swap; this is what takes it down, and it is the only signal that means "the canvas you are
// looking at is the one you asked for".
//
// Posted rather than pushed: this is the frame's own LiveView, and the overlay belongs to the editor
// around it. A `postMessage` costs nothing and stays in the browser; a push would be a round trip
// per patch to tell the server something it already knows.
//
// The last revision announced lives as a JS property on the ELEMENT, the same place `FrameLoader`
// keeps `__pbLoaded` and for the same reason: a `data-*` the server did not render is stripped on
// the next patch, and a field on the hook is gone the moment LiveView remounts it.
// A COMPONENT THAT DRAWS NOTHING IS STILL A NODE ON THE PAGE. A pager with one page, a card handed
// no post, a slider whose stylesheet the frame does not load and a flash group pinned to the corner
// of the viewport all leave their box at zero pixels: the layers rail lists them and the canvas has
// nothing to point at, select or drop beside. `data-pb-blank` is what `#pb-canvas-chrome` gives a
// floor, a dashed edge and the component's name.
//
// MEASURED, because only the browser knows: whether a box is empty is a question about the site's
// stylesheet, a hook and the viewport as much as about the markup. What is measured is the CONTENT —
// the boxes of the elements directly inside and any words of its own — and never the box itself,
// which once floored measures its own floor; asking it that would take the floor off on the next
// patch and put it back on the one after. A box with no element inside is blank whatever it says.
//
// Only the editor's own boxes around a component, never a placeholder that already says what it
// wants (an overlay chip, a media well, a missing required field, a failed render).
const BLANK_SKIP = "[data-pb-overlay], [data-wants-media], [data-incomplete], [data-render-error]";

export function drawsNothing(el) {
  for (const child of el.childNodes) {
    if (child.nodeType === 3 && child.textContent.trim() !== "") return false;

    if (child.nodeType === 1) {
      const box = child.getBoundingClientRect();
      if (box.width >= 1 && box.height >= 1) return false;
    }
  }

  return true;
}

export function markBlanks(root) {
  for (const el of root.querySelectorAll('[data-pb-frame][data-node-id]')) {
    const blank = !el.matches(BLANK_SKIP) && drawsNothing(el);

    if (blank) el.setAttribute("data-pb-blank", "true");
    else el.removeAttribute("data-pb-blank");
  }
}

function announcePainted(el) {
  const revision = el.dataset.revision;
  if (revision === undefined || revision === el.__pbPainted) return;

  el.__pbPainted = revision;
  window.parent.postMessage({ pb: true, kind: "painted", revision }, window.origin);
}

const PbCanvas = {
  mounted() {
    // There is deliberately NO hover handler. The outline is a CSS rule inside the canvas document,
    // because nothing on the server consumes hover — the layers rail highlights the SELECTION, as the
    // prototype does. Pushing a `hover` event per mouseover meant a round trip and a re-render of the
    // whole document for every pixel the pointer travelled, which is what made selecting an element
    // take seconds: the click's diff queued behind hundreds of hover diffs, and LiveView's progress
    // bar flashed on each one.

    // A DOUBLE CLICK SAYS "I AM ABOUT TO TYPE", whatever it lands on. When it opens words for
    // editing, the keys that follow go into them. When it does not — it landed on a section's
    // padding, or the words it opened were taken away under the caret — the author still believes
    // they are typing, and Backspace is the first key they press. That key used to delete the
    // selected element: an e2e run double-clicked where a deleted heading had been, pressed
    // Backspace to clear the words it expected, and took out the section that had moved up into its
    // place, then the next one, then the next.
    //
    // `this.typing` remembers the belief until the author makes a new choice: a single click, a
    // selection made anywhere else, or Enter/Escape out of the words. While it holds and no text has
    // the caret, Delete and Cut are answered with what happened instead of acting (see `onKey`).
    this.typing = false;

    this.onDblClick = (event) => {
      if (previewing()) return;

      this.typing = true;

      // Where the gesture began, not what the first click drew under the pointer since — see
      // `onSelectClick`.
      const target = this.pressed || event.target;

      const hit = target.closest('[data-kind="text"]');
      if (!hit) return this.onDblSelect(event, target);

      // THE PRESS MAY BE A NODE THE PATCH HAS SINCE REDRAWN. The first click's own `select` re-renders
      // the frame, and a redraw can replace the element that was pressed: editing that one made a
      // detached copy editable, the caret went nowhere, and the keys meant for the words reached the
      // shortcuts instead. The id is what the gesture meant, so the live element is found by it.
      const node = hit.isConnected ? hit : textNodeById(hit.dataset.nodeId);

      // A double click inside the words already open is the browser's: it selects a word there.
      if (node && node !== this.editing) this.editText(node, event);
    };

    const textNodeById = (id) =>
      id
        ? this.el.ownerDocument.querySelector(`[data-kind="text"][data-node-id="${CSS.escape(id)}"]`)
        : null;

    this.editText = (node, event) => {
      // The id the author opened, read once: everything below must answer for this node, whatever a
      // patch writes onto the element while the words are open.
      const id = node.dataset.nodeId;

      // Where the pointer was, while the browser can still say — see `caretAt` — and whether the
      // element shows its line breaks, while it is still drawn as the page draws it.
      const aim = pointRange(node.ownerDocument, event);
      const shown = keepsBreaks(node);

      node.setAttribute("contenteditable", "plaintext-only");

      // LIVEVIEW MUST NOT REDRAW WORDS SOMEBODY IS TYPING. Any patch that re-renders this node —
      // the `set_text` of the words edited a moment before, an autosave, a co-editor — morphs the
      // element back to the server's HTML: `contenteditable` is not in it, so it was removed, the
      // browser blurred the words mid-sentence, `finish` sent whatever had been typed so far, and
      // the next key went to the page. The e2e run's history shows it: "Home" written back 24 ms
      // after the brand next to it, "Heading" 67 ms after the paragraph beside it, each followed by
      // a Backspace that deleted the element. `phx-update="ignore"` is LiveView's own word for
      // "this element's content is the browser's": it keeps the attributes it did not render and
      // leaves the children alone, and only `data-*` is merged. Removed again in `finish`.
      node.setAttribute("phx-update", "ignore");
      node.focus();
      caretAt(node, aim);
      this.editing = node;

      // COMMITTING IS A KEYSTROKE, not only a click somewhere else. Escape leaves, ⌘/Ctrl+Enter
      // saves, and plain Enter saves too — a heading or a button label is one line, and typing into
      // one and pressing Enter means "done", not "give me a second line". Shift+Enter is the way to
      // ask for the newline, which is the convention every editor with a one-line field uses.
      //
      // Escape leaves the WORDS, not the selection: it stops here, so the editor's own Escape does
      // not also drop the element the author was just editing.
      //
      // ⌘A/Ctrl+A SELECTS THESE WORDS AND NOTHING ELSE. Left to the browser it reaches past them
      // whenever the caret is not where the browser thinks the editing host is — the e2e run's
      // "Mishka StudioNorthwind" was select-all failing and the new title typed in front of the old
      // one — so it is answered here, from the node itself.
      //
      // ⌘↓ AND ⌘END GO TO THE END OF THESE WORDS, ⌘↑ AND ⌘HOME TO THE START, for the same reason. See
      // `runEdge`.
      const onKey = (ev) => {
        if (selectsAll(ev)) {
          ev.preventDefault();
          return selectContents(node);
        }

        const edge = runEdge(ev);
        if (edge) {
          ev.preventDefault();
          return caretToEdge(node, edge, ev.shiftKey, shown);
        }

        if (ev.key === "Escape") {
          ev.stopPropagation();
          this.typing = false;
          return node.blur();
        }

        if (ev.key !== "Enter") return;
        if (ev.shiftKey && !(ev.metaKey || ev.ctrlKey)) return;

        ev.preventDefault();
        this.typing = false;
        node.blur();
      };

      const finish = () => {
        node.removeEventListener("keydown", onKey);
        node.removeAttribute("phx-update");
        node.removeAttribute("contenteditable");
        if (this.editing === node) this.editing = null;
        this.pushEvent("set_text", { id, text: node.textContent, pre: shown });
      };

      node.addEventListener("blur", finish, { once: true });
      node.addEventListener("keydown", onKey);
    };

    // THE NODE ITSELF, WHEN THAT IS WHAT WAS MEANT. A single click resolves upwards, because the
    // words in a heading are the heading and an expression sitting alone in a `<div>` is, to anyone
    // pointing at it, that div's content. That is right for the common case and leaves no way at all
    // to reach the thing under the pointer: `{@size}` selected the div around it, the Inspector
    // showed the div, and the one node whose source somebody wanted to edit could not be selected
    // from the canvas at all.
    //
    // So the second click says "no, THAT one". Not a special case for expressions — any node the
    // single click would have resolved past, which is the same set on the same rule, so a comment
    // and a token behave the way an expression does without either being named here.
    this.onDblSelect = (event, target) => {
      const exact = target.closest("[data-node-id]");
      if (!exact) return;

      // Nothing was resolved past, so there is nothing a second click could mean that the first one
      // did not already do.
      if (styleableNode(target) === exact) return;

      event.preventDefault();
      event.stopPropagation();
      this.markSelected(exact.dataset.nodeId);
      this.pushEvent("select", { id: exact.dataset.nodeId });
    };

    this.onKey = (event) => {
      // The same repeat guard as the chrome's. This is the copy that matters: the caret is usually
      // inside the canvas, so this is where a held key would be caught.
      if (event.repeat) return;

      const shortcut = PB_SHORTCUTS(event);
      if (!shortcut) return;
      if (PB_FIELD_KEEPS(event, shortcut)) return;

      event.preventDefault();

      // WHAT THE AUTHOR CAN SEE, sent with the key. The ring is drawn here the moment a node is
      // clicked; the server's selection arrives a round trip later, and under load that is seconds.
      // A Delete pressed in between removed whatever the server still held — the e2e run lost its
      // hero, its call-to-action and its footer that way — so the chrome is told which element the
      // key was pressed on, and acts only when the two agree. `typing` is the belief above.
      window.parent.postMessage(
        {
          pb: true,
          kind: "shortcut",
          key: shortcut,
          node_id: this.selectedId || null,
          typing: this.typing === true,
        },
        window.origin,
      );
    };

    this.handleEvent("pb:drop-rejected", ({ message }) =>
      window.parent.postMessage({ pb: true, kind: "error", message }, window.origin),
    );

    this.handleEvent("pb:open-rail", ({ action }) =>
      window.parent.postMessage({ pb: true, kind: "rail", action }, window.origin),
    );

    // The preview bar's own way out, riding the shortcut channel because ⌘P already means exactly
    // this and the chrome already knows how to answer it.
    this.handleEvent("pb:leave-preview", () =>
      window.parent.postMessage({ pb: true, kind: "shortcut", key: "preview" }, window.origin),
    );

    // The selection RING is client state. The server still owns the selection — the inspector, the
    // layers rail and the toolbar all read it — but drawing the ring from a server render meant every
    // click re-rendered all ~70 nodes of the document, and a click took over half a second to show
    // anything. Marking the node here is instant, and the server's answer moves nothing that is
    // already right.
    //
    // A SLOT IS RINGED ON THE ELEMENT IT BELONGS TO. A component draws its slots inside its own
    // markup, so a `<:item>` selected in the layers rail has no `[data-node-id]` here, and with
    // nothing painted the rules that keep an overlay open while something in it is selected let an
    // opened sidebar fall shut. `anchor` is the server's nearest drawn ancestor (`selection_anchor/2`
    // in `CanvasLive`), kept so `updated()` paints it again; the selection itself stays the slot.
    this.markSelected = (id, anchor = null) => {
      const doc = this.el.ownerDocument;
      // THE PANEL BELONGS TO THE ELEMENT IT WAS OPENED ON. It survives a patch — that is what lets
      // someone try six spreads in a row — but a NEW selection is a new question, and carrying the
      // open panel over to it both hides the element just clicked and offers rows that describe
      // something else.
      const previous = this.selectedId;
      // A ring that moved is a new choice, and ends the "about to type" of a double click before it.
      if ((id || null) !== previous) {
        this.layoutOpen = false;
        this.typing = false;
      }
      this.selectedId = id || null;
      this.selectedAnchor = (id && anchor) || null;
      doc
        .querySelectorAll('[data-node-id][data-selected="true"]')
        .forEach((el) => el.removeAttribute("data-selected"));
      if (!id) return this.placeToolbar?.();
      const drawn = (nodeId) => doc.querySelector(`[data-node-id="${CSS.escape(nodeId)}"]`);
      const node = drawn(id) || (this.selectedAnchor && drawn(this.selectedAnchor));
      if (node) node.setAttribute("data-selected", "true");
      // A SELECTION MADE SOMEWHERE ELSE HAS TO BE FINDABLE. Clicking a review note anchored to an
      // element three screens down used to ring something nobody could see. A selection made ON the
      // canvas is already in view by definition, so only bring it into view when the ring moved.
      if (node && id !== previous) node.scrollIntoView({ block: "nearest", behavior: "smooth" });
      // The floating toolbar is positioned from the selected element's box, so it has to move WITH
      // the ring. A selection made in the layers rail arrives as a push_event AFTER the DOM patch
      // that rendered the toolbar, so repositioning only on `updated()` left the bar wherever the
      // previous selection had put it — usually the bottom-left of the canvas.
      this.placeToolbar?.();
    };

    // Selections made ANYWHERE — the layers rail, a comment's deep link, undo — arrive here.
    this.handleEvent("pb:selected", ({ id, anchor }) => this.markSelected(id, anchor));

    // The held elements, painted the same way the ring is: an id list the client applies, never
    // `data-marked` rendered per node — that would re-render the whole document on every ⌘-click.
    this.handleEvent("pb:marked", ({ ids }) => {
      const doc = this.el.ownerDocument;
      const held = new Set(ids);

      for (const el of doc.querySelectorAll("[data-marked='true']")) {
        if (!held.has(el.dataset.nodeId)) el.removeAttribute("data-marked");
      }

      for (const id of held) {
        doc.querySelector(`[data-node-id="${CSS.escape(id)}"]`)?.setAttribute("data-marked", "true");
      }
    });

    // PREVIEW IS READ-ONLY, AND THAT HAS TO MEAN EVERY WAY IN. The flag was read here and nowhere
    // else, so selection was off while double-click still rewrote text and a drag still moved
    // nodes — a mode that says "this is how visitors see it" while quietly letting you edit it.
    const previewing = () => this.el.dataset.preview === "true";

    // WHAT WAS CLICKED IS NOT ALWAYS WHAT CAN BE EDITED. A run of text, an EEx expression and a
    // comment carry no attributes and no classes of their own — `Node.container?/1` is the server's
    // word for it, and the inspector already answers a click on one with a near-empty panel whose
    // only offer is a button reading "Style the element around it". So clicking the words in a
    // heading cost two clicks to reach the heading, or a trip to the layers rail.
    //
    // On the canvas the words ARE the heading. Both click paths resolve through this: the ordinary
    // one below, and `onCapture`, which answers clicks on links and submits — those are the words
    // most likely to be clicked, and resolving in only one of the two would have made a nav link
    // behave differently from a paragraph.
    //
    // Nothing is lost. Double-click still edits the words, because that handler looks for
    // `[data-kind="text"]` under the pointer and never consults the selection, and the layers rail
    // can still select a run on its own for anyone who wants exactly that.
    const STYLEABLE = new Set(["tag", "component", "slot"]);

    const styleableNode = (target) => {
      let node = target.closest("[data-node-id]");

      while (node && node.dataset.kind && !STYLEABLE.has(node.dataset.kind)) {
        const around = node.parentElement && node.parentElement.closest("[data-node-id]");
        if (!around) break;
        node = around;
      }

      return node;
    };

    this.onSelectClick = (event) => {
      // A DOUBLE CLICK BELONGS TO WHAT WAS UNDER THE POINTER WHEN IT BEGAN. The first click selects
      // the element around the pointer, and that can change what is under it before the second one
      // lands: an element near the top of the frame is scrolled down, clear of the toolbar's band,
      // and the toolbar takes the spot the chip left; one taller than the frame gets the toolbar
      // pinned over its content. The second click then pressed whichever toolbar button had slid
      // under the pointer, and the `dblclick` found no node there and did nothing — the expression
      // the gesture was aimed at could not be reached.
      //
      // So the press that starts a gesture is kept and answers the `dblclick`, and the rest of the
      // gesture is no click of its own — the first one already selected. Stopped outright, so no
      // toolbar button, link guard or LiveView binding hears it, and prevented, because the link
      // guard is skipped along with them. Kept until the next single click rather than the
      // `dblclick`, so the third press of a triple-click is swallowed too. A gesture begun ON the
      // toolbar is the toolbar's own; one that leaves preview halfway still answers from its own
      // first press, which is why this runs before the preview check.
      if (event.detail <= 1) {
        this.pressed = event.target.closest("#pb-el-toolbar") ? null : event.target;
        // A single click is a new choice, unless it only moved the caret inside the open words.
        if (!this.editing?.contains(event.target)) this.typing = false;
      } else if (this.pressed && !previewing()) {
        event.preventDefault();
        return event.stopImmediatePropagation();
      }

      if (previewing()) return;
      if (event.target.closest("a[href], button[type=submit], form")) return;
      // THE TOOLBAR IS NOT THE DOCUMENT. It lives in the top layer, outside every `[data-node-id]`,
      // so a click on its own buttons read as "clicked empty space" and dropped the ring — then
      // `placeToolbar` hid the bar the reader had just pressed. Every action on it acts on the
      // CURRENT selection, so pressing one must never change what is selected.
      //
      // AND IT ACTS ON THE ELEMENT IT NAMES. The bar is the server's selection, drawn where the ring
      // is; for the round trip after a click the two differ, and the bar sits on the new element
      // while it still names, and deletes, the old one. Its actions wait until the two agree, the
      // same rule the keyboard follows (see `onKey`).
      if (
        event.target.closest('#pb-el-toolbar [phx-click="toolbar"]') &&
        (this.el.dataset.selection || null) !== (this.selectedId || null)
      ) {
        event.preventDefault();
        return event.stopImmediatePropagation();
      }

      if (event.target.closest("#pb-el-toolbar")) return;

      const node = styleableNode(event.target);

      // ⌘ OR CTRL HOLDS A SECOND ELEMENT rather than replacing the first. The `phx-click="select"`
      // on the node would still fire and throw the held ones away, so the click is stopped here and
      // re-sent as a mark.
      if (node && (event.metaKey || event.ctrlKey)) {
        event.preventDefault();
        event.stopPropagation();
        return this.pushEvent("mark", { id: node.dataset.nodeId });
      }

      // A COMPONENT'S OWN BEHAVIOUR IS NOT THE EDITOR'S. A kit component may carry its own
      // `phx-click` — flash, toast, banner, badge, rating and pagination all do — and a dismiss is
      // `JS.push(...)` followed by `JS.hide(to: "#its-own-id")`. LiveView binds the INNERMOST
      // `phx-click`, which is the component's and not the wrapper's `select`, so clicking one in the
      // canvas ran its dismiss: the element went `display:none` on the client, the server never
      // heard about it, and because `contain/2` flattens a component to a single static blob nothing
      // ever re-sent that markup. The author saw the component they had just placed vanish, with the
      // code still holding it and no way back but a reload.
      //
      // In the canvas a component is a picture of itself, so its behaviour is stopped and the click
      // means what every other click here means: select this node. Preview mode returns above, where
      // a click is the page's rather than the editor's — a live component is still drawn cold there,
      // and runs only on the published page.
      const bound = event.target.closest("[phx-click]");

      if (node && bound && bound !== node && node.contains(bound)) {
        event.preventDefault();
        event.stopPropagation();
        this.markSelected(node.dataset.nodeId);
        return this.pushEvent("select", { id: node.dataset.nodeId });
      }

      // Resolving upwards means the wrapper under the pointer would still report ITS id, so the
      // click is stopped and re-sent for the one that was resolved to.
      const clicked = event.target.closest("[data-node-id]");

      if (node && clicked && node !== clicked) {
        event.preventDefault();
        event.stopPropagation();
        this.markSelected(node.dataset.nodeId);
        return this.pushEvent("select", { id: node.dataset.nodeId });
      }

      this.markSelected(node ? node.dataset.nodeId : null);
    };
    this.el.ownerDocument.addEventListener("click", this.onSelectClick, true);

    // Deselect only when the click actually missed every node. A `phx-click` on the container would
    // fire on the way up from a node's own click and cancel the selection that just happened.
    this.onClick = (event) => {
      // A link or a submit button inside the document must not act. The canvas is an editing
      // surface: clicking `<a href="/">` to select it navigated the whole editor away — LiveView's
      // own interceptor treated the page's `data-phx-link` anchor as a live redirect.
      // Links and submits are handled in the capture listener below; this only has to deal with a
      // click that missed every node, which is what clears the selection.
      if (event.target.closest("a[href], button[type=submit], form")) return;
      if (event.target.closest("#pb-el-toolbar")) return;
      // NOT IN PREVIEW. Clearing the selection there moves the Inspector while editing is off, and
      // with a palette item armed the same empty `select` places it.
      if (previewing()) return;
      if (!event.target.closest("[data-node-id]")) this.pushEvent("select", {});
    };

    // THE MENU LIVES IN THE CHROME, NOT IN HERE. This frame renders the SITE's document and never
    // loads the admin stylesheet, so a menu drawn here would arrive unstyled — and building a second
    // inline-styled copy of it is exactly the drift the shared component exists to prevent. The
    // right-click is forwarded instead, with its point; the chrome translates it through the frame's
    // own box and opens the one menu there.
    this.onContext = (event) => {
      // Not in preview: that menu is the editor's — wrap, cut, delete — and choosing any entry selects
      // the node it was opened on. The browser's own menu is what a visitor gets.
      if (previewing()) return;

      const node = event.target.closest("[data-node-id]");
      if (!node) return;

      event.preventDefault();
      window.parent.postMessage(
        {
          pb: true,
          kind: "context",
          id: node.dataset.nodeId,
          // Hidden from visitors, itself or with what is around it: the menu's entry says Show.
          hidden: !!node.closest("[data-pb-hidden]"),
          x: event.clientX,
          y: event.clientY,
        },
        window.origin,
      );
    };

    this.el.ownerDocument.addEventListener("contextmenu", this.onContext);

    // ---- drag and drop -------------------------------------------------------------------
    // Hybrid, in the sense the two halves answer two different questions:
    //
    //   * GEOMETRY is the browser's. Where the pointer sits inside a box decides "before", "after"
    //     or "inside", and that is resolved here, per pointer move, with no round trip — which is
    //     why NOTHING is pushed on hover. (Pushing per hover is what once made this editor take
    //     seconds per gesture; see the note at the top of this hook.)
    //   * LEGALITY is the server's. `pb:drop-hints` arrives ONCE, at dragstart, carrying the whole
    //     tree's verdict for the thing being dragged — computed by the same function that later
    //     admits or refuses the drop, so the line cannot promise something the server will reject.
    //     Until it lands (a few ms) the resolver guesses optimistically and the server is still the
    //     one that decides; if it refuses, `EditorSession.apply_drop/2` places the node beside the
    //     target instead of losing the gesture, and says so.
    //
    // Rects are cached for the life of one drag and the indicator is only touched when the resolved
    // position actually changes: reading a box and then writing a style, per dragover, forced a
    // synchronous layout of the whole document on every pointer move.
    const indicator = document.createElement("div");
    indicator.style.cssText =
      "position:absolute;left:0;top:0;z-index:2147483647;pointer-events:none;background:#3a6cf4;" +
      "display:none;border-radius:2px;will-change:transform;";

    // Names where a redirected drop is actually going. A silently moved drop is the one thing worse
    // than a refused one. A field adds the form it joins, or that it starts one, in a part of its own.
    const caption = document.createElement("span");
    caption.style.cssText =
      "position:absolute;left:0;top:-18px;white-space:nowrap;font:600 10px/1.6 ui-sans-serif,system-ui;" +
      "display:none;gap:3px;";
    const captionPart = () => {
      const part = document.createElement("span");
      part.style.cssText = "padding:0 6px;border-radius:4px;background:#b45309;color:#fff;";
      caption.appendChild(part);
      return part;
    };
    const captionBase = captionPart();
    const captionForm = captionPart();
    indicator.appendChild(caption);
    document.body.appendChild(indicator);
    this.indicator = indicator;

    let rects = new Map();
    const rectOf = (el) => {
      let rect = rects.get(el);
      if (!rect) rects.set(el, (rect = el.getBoundingClientRect()));
      return rect;
    };

    // `pb_drop.js` owns the geometry — rows against stacks, reversed rows, the climb out of a
    // container that will not take the node. It is a pure function of four lookups, which is what
    // lets it be tested against plain rectangles instead of a rendered page.
    let axes = new Map();
    const styleOf = (el) => {
      if (!el) return null;
      let style = axes.get(el);
      if (!style) axes.set(el, (style = getComputedStyle(el)));
      return style;
    };

    this.forgetRects = () => {
      rects.clear();
      axes.clear();
    };

    // A CONTAINER WITH NOTHING IN IT HAS NO HEIGHT, so there was nowhere to aim: an empty column in
    // a fresh row collapses to 0px and the pointer went straight through it to whatever was behind.
    // For the length of one drag they get a floor and a dashed edge — the JS owns this, so nothing
    // has to be rendered per node and no class needs the runtime compiler to have seen it.
    let opened = [];

    // WHATEVER THE POINTER IS AIMED AT MUST NOT MOVE. Giving every empty container a 34px floor
    // changes the height of the whole document, so anything below the first opened box slides down
    // mid-gesture — an author aiming under a table watched the table itself jump away as the blocks
    // appeared above it. The floors are still worth having (a fresh 0px column is unreachable
    // without them); what is not worth having is the page moving under the cursor.
    //
    // So: measure the node under the pointer before opening, measure it again after, and scroll by
    // the difference. The document grew, the thing being aimed at did not move, and the cached drop
    // boxes are dropped because every one of them is now wrong.
    const anchorFor = (event) => {
      const el =
        (event && event.target && event.target.closest && event.target.closest("[data-node-id]")) ||
        (event &&
          this.el.ownerDocument.elementFromPoint &&
          this.el.ownerDocument.elementFromPoint(event.clientX, event.clientY));

      return el && el.getBoundingClientRect ? el : null;
    };

    const openEmpties = (event) => {
      const anchor = anchorFor(event);
      const before = anchor && anchor.getBoundingClientRect().top;

      openEmptiesNow();

      if (anchor === null || before === null) return;

      const after = anchor.getBoundingClientRect().top;
      const scroller = this.el.ownerDocument.scrollingElement;

      if (scroller && after !== before) {
        scroller.scrollTop += after - before;
        this.forgetRects();
      }
    };

    const openEmptiesNow = () => {
      // A box THIS CODE already opened measures the 34px floor it was given, so the height test
      // below reads it as content and skips it — and the entry holding its real styles would be
      // dropped with the rest of the list, leaving nothing to restore it with. It is carried over
      // instead: a node stays this hook's responsibility until it is closed.
      const held = new Map(opened.map((entry) => [entry[0], entry]));
      opened = [];
      // `:not([data-ws])` marks a node that holds a place without being content — the indentation
      // left behind when a container is emptied, and anything folded away with the eye, a comment
      // included. Counting either as content leaves the one box that most needs a floor without one.
      for (const el of this.el.querySelectorAll("[data-node-id]")) {
        if (!nests(el) || el.querySelector("[data-node-id]:not([data-ws])")) continue;
        if (held.has(el)) {
          opened.push(held.get(el));
          continue;
        }
        if (el.getBoundingClientRect().height > 18) continue;
        opened.push([
          el,
          el.style.minHeight,
          el.style.outline,
          el.style.outlineOffset,
          el.style.background
        ]);
        // The same tone the render path already uses for a hollow box. 34px of white inside a hard
        // blue dash reads as a broken layout rather than as a place to aim.
        el.style.minHeight = "34px";
        el.style.outline = "1px dashed #c9c7ee";
        el.style.outlineOffset = "-1px";
        el.style.background = "rgba(91, 87, 214, 0.04)";
      }
    };

    const closeEmpties = () => {
      for (const [el, minHeight, outline, offset, background] of opened) {
        el.style.minHeight = minHeight;
        el.style.outline = outline;
        el.style.outlineOffset = offset;
        el.style.background = background;
      }
      opened = [];
    };

    // AUTO-SCROLL AT THE EDGES. `edgeVelocity` decides how fast; one rAF loop applies it for the
    // whole drag and is cancelled the moment the gesture ends. Every scrolled pixel invalidates the
    // cached boxes, so the line keeps pointing where the pointer really is.
    //
    // AND THE LINE IS REDRAWN AS THE PAGE MOVES. A pointer resting near an edge sends no `dragover`
    // of its own — the browser repeats one every few hundred milliseconds, at up to 18px a frame of
    // scrolling in between — so the line stayed on the box the pointer had been over while another
    // slid under it, and the drop, which was resolved again, landed somewhere the line never showed.
    let scrollBy = 0;
    let scrolling = null;

    const runScroll = () => {
      if (!scrollBy) return (scrolling = null);
      const scroller = this.el.ownerDocument.scrollingElement;
      if (scroller) {
        scroller.scrollTop += scrollBy;
        rects.clear();
        this.reaimDrop?.();
      }
      scrolling = requestAnimationFrame(runScroll);
    };

    const edgeScroll = (event) => {
      scrollBy = edgeVelocity(event.clientY, this.el.ownerDocument.documentElement.clientHeight);
      if (scrollBy && !scrolling) scrolling = requestAnimationFrame(runScroll);
    };

    const stopScroll = () => {
      scrollBy = 0;
      if (scrolling) cancelAnimationFrame(scrolling);
      scrolling = null;
    };

    let painted = null;
    const hideIndicator = () => {
      painted = null;
      indicator.style.display = "none";
    };

    // The server's verdict when it has arrived, an optimistic yes when it has not. Unknown ids —
    // the document root — accept: the tree always has somewhere to put a node.
    const accepts = (id) => {
      const hints = window.__pbDropHints;
      return !hints || hints[id] !== false;
    };

    const nests = (node) => {
      const hints = window.__pbDropHints;
      if (hints) return hints[node.dataset.nodeId] === true;
      return node.dataset.kind !== "text" && node.dataset.kind !== "eex";
    };

    const parentOf = (node) => node.parentElement?.closest("[data-node-id]") || null;

    // A runtime component is named by what the author called it, not by the `div` it renders into.
    const labelOf = (node) => node.dataset.component || node.tagName.toLowerCase();

    // Everything the resolver needs to read off the page. It asks for these rather than reaching for
    // the DOM itself, which is what lets the geometry be checked against plain rectangles.
    const lookup = {
      rectOf,
      styleOf,
      parentOf,
      // NOT ONLY DIRECT CHILDREN. A runtime component renders its slot children through its own
      // markup, so they sit several elements deep inside the component's wrapper with no wrapper of
      // their own. Reading direct children alone found none of them, `indexOf` answered -1, and the
      // drop was appended to the end of the component instead of landing in the slot.
      //
      // The descendant sweep is filtered back to the ones this element really parents, so a node
      // nested inside ANOTHER node is not counted as a sibling of it.
      childrenOf: (parent) => {
        const host = parent || this.el;
        const direct = [...host.children].filter((el) => el.dataset.nodeId);
        if (direct.length) return direct;

        return [...host.querySelectorAll("[data-node-id]")].filter(
          (el) => parentOf(el) === parent
        );
      },
      idOf: (el) => el.dataset.nodeId,
      labelOf,
      accepts,
      nests,
    };

    // What a field drag reads off the canvas: the forms the server marked (`data-pb-form`, their
    // people name) and the node a drop at a form's end lands in front of (`data-pb-send`).
    const formLookup = {
      byId: (id) =>
        this.el.ownerDocument.querySelector(`[data-node-id="${CSS.escape(String(id))}"]`),
      isForm: (el) => !!el && el.hasAttribute("data-pb-form"),
      formOf: (el) => (el && el.closest ? el.closest("[data-pb-form]") : null),
      nameOf: (form) => form.getAttribute("data-pb-form") || "",
      landingOf: (form) => form.querySelector("[data-pb-send]"),
      precedes: (a, b) =>
        a !== b &&
        !a.contains(b) &&
        !b.contains(a) &&
        !!(b.compareDocumentPosition(a) & Node.DOCUMENT_POSITION_PRECEDING),
      contains: (a, b) => a === b || a.contains(b),
    };

    // A line in front of `el`, along the way its siblings run.
    const before = (el) => ({
      rect: rectOf(el),
      axis: axisOf(styleOf(parentOf(el))).axis,
      before: true,
      inside: false,
    });

    const resolveDrop = (event) =>
      resolveDropAt(
        { x: event.clientX, y: event.clientY },
        event.target.closest("[data-node-id]"),
        lookup,
      );

    // WHAT THE LINE SAYS IS WHAT THE DROP DOES. `aimed` is the target the line was last drawn for and
    // `pointer` where the pointer was, both for this frame's part of the gesture. The drop used to be
    // resolved a second time, against a page that had moved since the line was drawn — scrolled at
    // an edge, or a verdict arrived — so the two could disagree, and the one the author saw lost.
    let aimed = null;
    let pointer = null;

    const forgetAim = () => {
      aimed = null;
      pointer = null;
    };

    // Drawn again for the same pointer, when what is under it or what it may hold has changed.
    this.reaimDrop = () => {
      if (!pointer) return;

      const doc = this.el.ownerDocument;
      const under = doc.elementFromPoint && doc.elementFromPoint(pointer.x, pointer.y);
      const node = under && under.closest ? under.closest("[data-node-id]") : null;

      aimed = resolveDropAt(pointer, node, lookup);
      paint(aimed);
    };

    // How far an "inside" outline reaches past the container's own bounds. A box drawn AROUND the
    // container reads as the thing opening up to take the drop; a faint tint over the same box was
    // easy to miss, and on a short element — a collapsed alert is 24px tall — it was
    // indistinguishable from the line.
    const GROW = 4;

    const tones = { violet: "#7c3aed", blue: "#3a6cf4" };

    const paint = (target) => {
      const field = target.rect && window.__pbFieldDrag ? formLanding(target, formLookup) : null;
      const joins = field && formCaption(field);
      const key = target.rect
        ? `${target.parent_id}|${target.index}|${!!target.inside}|${!!target.redirected}|` +
          `${joins ? joins.text : ""}|${field && field.landing ? field.landing.dataset.nodeId : ""}`
        : null;
      if (key === painted) return;
      painted = key;

      // A field is drawn where it will land: in front of the Send button a spot past it moves to.
      const shown = field && field.landing ? before(field.landing) : target;
      const box = indicatorBox(shown, GROW);
      if (!box) return hideIndicator();

      const colour = target.redirected ? "#d97706" : "#3a6cf4";

      indicator.style.display = "block";
      indicator.style.transform =
        `translate3d(${box.left + window.scrollX}px, ${box.top + window.scrollY}px, 0)`;
      indicator.style.width = `${box.width}px`;
      indicator.style.height = `${box.height}px`;
      indicator.style.background = shown.inside ? "rgba(58,108,244,.08)" : colour;
      indicator.style.border = shown.inside ? `2px solid ${colour}` : "none";
      indicator.style.borderRadius = shown.inside ? "8px" : "2px";
      indicator.style.boxShadow = shown.inside ? `0 0 0 4px rgba(58,108,244,.10)` : "none";

      const base = target.inside
        ? `inside <${target.label}>`
        : target.redirected
          ? `after <${target.label}>`
          : "";

      captionBase.textContent = base;
      captionBase.style.display = base ? "inline-block" : "none";
      captionBase.style.background = colour;
      captionForm.textContent = joins ? (base ? `· ${joins.text}` : joins.text) : "";
      captionForm.style.display = joins ? "inline-block" : "none";
      captionForm.style.background = joins ? tones[joins.tone] : colour;
      caption.style.display = base || joins ? "flex" : "none";
    };

    // One request per drag, not per hover. The answer is stored on `window` rather than on the hook
    // because a drag that STARTED in the palette begins in the parent document — that side asks, and
    // the reply is handed to every canvas frame (see the `phx:pb:drop-hints` listener below).
    // THE FRAME TALKS UPWARDS. A drag that starts in here is answered by the CANVAS's own LiveView,
    // so the verdict lands in this document — and the layers rail, which the pointer is about to
    // cross into, lives in the parent one and would never see it. The hand-off already existed in
    // the other direction (`PbShortcuts` gives every frame the parent's copy); this is the return
    // leg, and without it every canvas-to-rail drag ran on an optimistic guess.
    const toParent = (payload) =>
      window.parent !== window &&
      window.parent.postMessage({ pb: true, ...payload }, window.origin);

    // Whether a field is being dragged in this frame: read by `paint`, and outlining its forms.
    const fieldDrag = (field) => {
      window.__pbFieldDrag = !!field;
      markFieldDrag(this.el.ownerDocument, field);
    };

    // What is being moved, faded while it is in flight. Without it the page looks unchanged for the
    // whole gesture and the only thing that says a drag is happening is a line somewhere else.
    let lifted = null;
    const lift = (node) => {
      lifted = [node, node.style.opacity];
      node.style.opacity = "0.4";
    };

    const drop = () => {
      if (lifted) lifted[0].style.opacity = lifted[1];
      lifted = null;
    };

    this.onDragStart = (event) => {
      if (previewing()) return event.preventDefault();

      const node = event.target.closest("[data-node-id]");
      if (!node) return;
      this.dragging = node.dataset.nodeId;
      window.__pbDropHints = null;
      fieldDrag(false);
      this.forgetRects();
      lift(node);
      openEmpties(event);
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", this.dragging);
      event.dataTransfer.setData(NODE_MIME, this.dragging);
      this.pushEvent("drag_start", { node_id: this.dragging });
      toParent({ kind: "drag", node_id: this.dragging });
    };

    // The effect has to MATCH what the source allowed, or the browser cancels the whole gesture: a
    // palette card sets `effectAllowed = "copy"`, and answering "move" made Chrome refuse the drop
    // silently — `dragleave` with `dropEffect: "none"` and no `drop` event at all. That is why a
    // component could be click-to-placed but never dragged in.
    //
    // A ROW DRAGGED OUT OF THE LAYERS RAIL allows "move" and nothing else, and it started in the
    // parent document so `this.dragging` is null here — answering "copy" to it was the same refusal
    // in mirror image, which is why a node could be reordered in the tree but never dragged from the
    // tree onto the page. `types` is the only part of a dataTransfer that is legible during a drag
    // (the values are held back until `drop`), which is what the marker type is for.
    const nodeDrag = (event) =>
      !!this.dragging || [...(event.dataTransfer?.types || [])].includes(NODE_MIME);

    // A DRAG THIS EDITOR STARTED — a canvas node or the grip, a row out of the rail, a palette or
    // snippet card, which between them set one of the two markers. Anything else was carried in
    // from outside the browser: a file out of Finder, a selection out of another tab. Those have no
    // source node in either of our documents, so the browser fires `dragend` nowhere we listen and
    // the broadcast below never runs — whatever such a drag opened would stand for the rest of the
    // session. It has no business inflating the author's layout to begin with.
    const editorDrag = (event) =>
      nodeDrag(event) || [...(event.dataTransfer?.types || [])].includes(TEMPLATE_MIME);

    const allow = (event) => {
      event.preventDefault();
      event.dataTransfer.dropEffect = nodeDrag(event) ? "move" : "copy";
    };

    // `dragenter` has to be accepted too, not just `dragover`. Entering an element makes it the
    // current drop target in its DEFAULT state — refusing — and if the button comes up before the
    // next `dragover` lands, the drop is discarded. A drag that crosses INTO the frame and releases
    // in one motion, which is exactly how a palette card is dropped, hits that window every time.
    // A palette card's drag begins in the PARENT document, so this frame never sees a `dragstart`
    // for it — the empty containers have to open when the pointer first crosses in, or the one
    // gesture the whole tray exists for is the one that cannot reach a fresh column.
    //
    // PREVIEW TAKES NO DROP. The canvas answers no edit there, so accepting the drag would draw a
    // landing line for a drop that changes nothing. It is still TAKEN rather than left alone: a drag
    // the page does not cancel is the browser's, and the browser's answer to a file or a link carried
    // in from outside is to open it, taking the frame away from the document. Cancelled with an
    // effect of "none", the drag shows as refused and no `drop` fires at all.
    const refuse = (event) => {
      event.preventDefault();
      event.dataTransfer.dropEffect = "none";
    };

    this.onDragEnter = (event) => {
      if (previewing()) return refuse(event);

      allow(event);
      if (!opened.length && editorDrag(event)) openEmpties(event);
    };

    this.onDragOver = (event) => {
      if (previewing()) return refuse(event);

      allow(event);
      edgeScroll(event);
      pointer = { x: event.clientX, y: event.clientY };
      aimed = resolveDrop(event);
      paint(aimed);
    };

    // `dragleave` bubbles, so crossing from one nested element to the next fires it on the canvas
    // even though the pointer never left — which made the line blink out and back on every boundary
    // and read as lag. Only a pointer that has actually left the canvas hides it.
    this.onDragLeave = (event) => {
      if (event.relatedTarget && this.el.contains(event.relatedTarget)) return;
      stopScroll();
      hideIndicator();
      forgetAim();
    };

    this.onDrop = (event) => {
      event.preventDefault();

      // The spot the line shows, or — for a drop with no `dragover` before it — resolved now, while
      // the page still has the shape the browser aimed it at: closing the empty containers below
      // collapses every one of them.
      const target = aimed || resolveDrop(event);

      stopScroll();
      closeEmpties();
      drop();
      hideIndicator();
      forgetAim();

      const payload = { parent_id: target.parent_id, index: target.index };

      // The tree, not the screen, decides where this goes — see `resolveDrop`.
      if (target.anchor_id) {
        payload.anchor_id = target.anchor_id;
        payload.anchor_before = target.anchor_before;
      }

      // Where a box the server refuses puts it instead — see `resolveDrop`.
      if (target.inside) payload.fallback_before = target.fallback_before;

      // A node dragged from inside the canvas is a move, and so is one dragged in from the layers
      // rail — that one begins in the parent document, so its id arrives on the dataTransfer rather
      // than on this hook. Anything else is the palette's template.
      const template = event.dataTransfer.getData(TEMPLATE_MIME);
      const moving = this.dragging || event.dataTransfer.getData(NODE_MIME);
      if (moving) payload.node_id = moving;
      else if (template) payload.template = template;
      else return;

      this.dragging = null;
      window.__pbDropHints = null;
      this.forgetRects();
      this.pushEvent("drop", payload);
    };

    // Everything this frame put on the author's document for the length of the gesture. Closing the
    // empty containers is the largest geometry change this hook makes, so the boxes measured against
    // the open layout go with them — whichever end the gesture came to.
    const restore = () => {
      stopScroll();
      closeEmpties();
      drop();
      hideIndicator();
      forgetAim();
      fieldDrag(false);
      this.forgetRects();
    };

    this.onDragEnd = () => {
      this.dragging = null;
      window.__pbDropHints = null;
      restore();
      toParent({ kind: "dragend" });
    };

    // THE GESTURE ENDED WHERE THIS FRAME CANNOT SEE IT — released over the palette, over the layers
    // rail, or cancelled. `dragend` fires on the source, which for all three is the chrome's
    // document, so the browser never tells this frame and the empty containers it opened kept their
    // floor and dashed edge until an unrelated edit repainted the node. The chrome broadcasts the
    // end into every frame instead (`endDrag`); this is the frame's half of it. Nothing is reported
    // back upwards — the chrome is where this came from.
    this.onDragAway = () => restore();

    // Auto-scrolling near an edge moves every box under the pointer, so a cached rect outlives its
    // truth by exactly one scroll. Capture phase catches inner scrollers too.
    this.el.ownerDocument.addEventListener("scroll", this.forgetRects, true);

    // A drag that starts INSIDE the canvas is answered by this frame's own LiveView, so the reply
    // lands here rather than in the chrome. `accepts` is read by `accepts/1` and `nests/1` above;
    // until it arrives they fall back to an optimistic yes, which is what the whole gesture used to
    // run on.
    // A reply that lands after this frame's drag ended is dropped, and not handed upwards either.
    //
    // The line is drawn again the moment the verdict lands, here or handed in by the chrome
    // (`pb:hints`, from `spreadHints`): drawn before it, it was the optimistic guess, and a pointer
    // held still would have kept showing that guess until it moved.
    this.handleEvent("pb:drop-hints", ({ accepts, field }) => {
      if (!this.dragging) return;
      window.__pbDropHints = accepts;
      fieldDrag(field);
      this.reaimDrop();
      toParent({ kind: "hints", accepts, field: !!field });
    });

    this.onHints = () => this.reaimDrop();
    window.addEventListener("pb:hints", this.onHints);

    this.handleEvent("pb:drop-moved", ({ message }) =>
      window.parent.postMessage({ pb: true, kind: "info", message }, window.origin),
    );

    // The floating element toolbar is positioned from the selection's bounding box rather than
    // nested inside it: putting it in the node would need `position:relative` on the author's own
    // element, which can silently change their layout.
    // The toolbar lives in the TOP LAYER (`popover`), so nothing in the author's document can paint
    // over it, and it is positioned in VIEWPORT coordinates — which is why it is repositioned on
    // scroll rather than moving with the page.
    const clamp = (value, low, high) => Math.max(low, Math.min(value, Math.max(low, high)));

    const showBar = (bar) => {
      bar.style.display = "flex";
      try {
        if (!bar.matches(":popover-open")) bar.showPopover();
      } catch (_unsupported) {
        // No popover support: the inline z-index still puts it above ordinary content.
      }
    };

    const hideBar = (bar) => {
      bar.style.display = "none";
      try {
        if (bar.matches(":popover-open")) bar.hidePopover();
      } catch (_unsupported) {}
    };

    this.placeToolbar = () => {
      const bar = this.el.ownerDocument.getElementById("pb-el-toolbar");
      const selected = this.el.querySelector('[data-selected="true"]');
      if (!bar) return;
      if (!selected) {
        this.layoutOpen = false;
        return hideBar(bar);
      }

      showBar(bar);
      this.applyLayoutOpen?.();

      const rect = selected.getBoundingClientRect();
      const view = this.el.ownerDocument.defaultView;
      const gap = 6;
      const height = bar.offsetHeight || 26;

      // ALWAYS the top edge. Just above the element when it fits, and pinned to the top of the frame
      // when the element's own top is scrolled out of view — which is the case that matters, because
      // selecting a full-page container used to send the bar to the BOTTOM of the screen, nowhere
      // near the thing it names. It is never sent below the element: the label belongs to the top.
      // Pinned is also ON the element, over whatever the author was pointing at in it, so the stage
      // and the scroll keep a band this tall clear above the document — the rule in
      // `#pb-canvas-chrome`, which has to change with the gap, the inset or the bar's height.
      const top = clamp(rect.top - height - gap, 4, view.innerHeight - height - 4);
      const left = clamp(rect.left, 4, view.innerWidth - bar.offsetWidth - 4);

      bar.style.left = `${left}px`;
      bar.style.top = `${top}px`;
    };

    // THE RING IS CLIENT STATE, so a frame that has just mounted has none — even when the session
    // it mounted from has had something selected all along. Nothing used to hand that over: the
    // server rendered the toolbar (it knows the selection) and this hook then hid it again, because
    // no node carried `data-selected`. Selecting from a panel looked like "the ring works but the
    // toolbar does not", and clicking anything in the frame first fixed it, which is what made it
    // look like a toolbar bug rather than a handover that never happened.
    //
    // One attribute on the root, read once. Not `data-selected` per node — that is still the
    // client's to paint, and rendering it per node would fight every patch.
    this.markSelected(this.el.dataset.selection || null, this.el.dataset.selectionAnchor || null);

    this.placeToolbar();
    window.addEventListener("scroll", this.placeToolbar, { passive: true });
    window.addEventListener("resize", this.placeToolbar);

    this.el.addEventListener("dblclick", this.onDblClick);
    this.el.addEventListener("click", this.onClick);

    // Capture phase, on the document: LiveView binds its own link interceptor further out, and a
    // `<a data-phx-link>` in the page would otherwise be treated as a live redirect and navigate the
    // canvas away from the document being edited. Capture runs before any of that.
    this.onCapture = (event) => {
      if (!event.target.closest?.("a[href], button[type=submit], form")) return;
      event.preventDefault();
      event.stopPropagation();

      // PREVIEW IS A PICTURE OF THE UNSAVED PAGE, NOT THE PAGE. A link there is still stopped — it
      // would take the frame away from the document — but it is not a selection either: the
      // Inspector changing under an author who clicked a post title to follow it reads as the click
      // having done something, with editing off.
      if (previewing()) return;

      // The ring moves now, as it does for every other click: a key pressed before the server
      // answers names what the author clicked, not the element ringed before it.
      const node = styleableNode(event.target);
      this.markSelected(node ? node.dataset.nodeId : null);
      this.pushEvent("select", node ? { id: node.dataset.nodeId } : {});
    };

    // MOUSEDOWN, NOT CLICK, and in the capture phase: a press on a link or a submit is stopped by
    // `onCapture` below and a press on the element toolbar never bubbles to the document at all, and
    // a menu left open through either of those is the bug being fixed. Posted on every press —
    // the chrome decides whether anything is open, which is not a question this frame can answer.
    this.onPress = () => window.parent.postMessage({ pb: true, kind: "dismiss" }, window.origin);
    this.el.ownerDocument.addEventListener("mousedown", this.onPress, true);

    this.onSubmit = (event) => event.preventDefault();
    this.el.ownerDocument.addEventListener("click", this.onCapture, true);
    this.el.addEventListener("submit", this.onSubmit);
    this.el.addEventListener("dragstart", this.onDragStart);
    // The toolbar's grip is the handle for MOVING the selection — the whole element, from the one
    // control that says so. It carried `cursor:grab` and nothing else, so it looked like a handle
    // and did nothing. It lives in the TOP LAYER, outside this hook's element, so it is bound
    // directly rather than through the canvas's own listeners.
    // Bound on the DOCUMENT, not on the grip: the toolbar is re-rendered whenever the selection
    // changes, and a listener attached to the element itself dies with the first patch.
    this.onGripDrag = (event) => {
      if (!event.target.closest?.("#pb-el-grip") || !this.selectedId) return;
      this.dragging = this.selectedId;
      window.__pbDropHints = null;
      rects.clear();
      event.dataTransfer.effectAllowed = "move";
      event.dataTransfer.setData("text/plain", this.dragging);
      // THE SAME MARKER THE NODE ITSELF SETS. Without it the grip moved the selection inside the
      // canvas — where `this.dragging` alone answers — and was invisible everywhere else: the rail
      // saw a drag carrying nothing it owned, never cancelled a `dragover`, and the browser fired no
      // `drop` at all. One handle, two behaviours, depending on where you let go.
      event.dataTransfer.setData(NODE_MIME, this.dragging);
      this.pushEvent("drag_start", { node_id: this.dragging });
      toParent({ kind: "drag", node_id: this.dragging });
    };

    // THE LAYOUT ROW OPENS IN THE BROWSER. It is already rendered — the server decided what it
    // contains when the selection changed — so revealing it needs no round trip, and asking for one
    // would patch the toolbar, restore the `display:none` its template carries and drop it out of
    // the top layer. Bound on the DOCUMENT because the toolbar is re-rendered on every selection and
    // a listener on the button itself dies with the first patch.
    // OPEN IS CLIENT STATE THAT MUST SURVIVE A PATCH. Choosing an option writes to the document, so
    // the server re-renders the toolbar — and the panel's own template carries `display:none`, which
    // the patch restores. Held only in the DOM, the panel therefore shut itself the moment you used
    // it, and trying a second option meant reopening it every time.
    //
    // The flag lives here and is re-applied in `placeToolbar`, which `updated()` already calls after
    // every patch — the same way the selection ring survives one.
    this.layoutOpen = false;

    this.applyLayoutOpen = () => {
      const row = this.el.ownerDocument.getElementById("pb-eltb-cols");
      if (row) row.style.display = this.layoutOpen ? "flex" : "none";
    };

    this.onLayoutToggle = (event) => {
      if (!event.target.closest?.("#pb-eltb-layout")) return;
      event.preventDefault();

      this.layoutOpen = !this.layoutOpen;
      this.applyLayoutOpen();
      this.placeToolbar?.();
    };

    this.el.ownerDocument.addEventListener("click", this.onLayoutToggle, true);
    this.el.ownerDocument.addEventListener("dragstart", this.onGripDrag, true);
    this.el.ownerDocument.addEventListener("dragend", this.onDragEnd, true);

    this.el.addEventListener("dragenter", this.onDragEnter);
    this.el.addEventListener("dragover", this.onDragOver);
    this.el.addEventListener("drop", this.onDrop);
    this.el.addEventListener("dragend", this.onDragEnd);
    this.el.addEventListener("dragleave", this.onDragLeave);
    window.addEventListener("keydown", this.onKey);
    window.addEventListener("pb:dragend", this.onDragAway);

    // On every patch, and again whenever a picture or a frame inside the canvas loads, because either
    // can give an empty box its content.
    this.blanks = () => {
      if (!previewing()) markBlanks(this.el);
    };
    this.el.ownerDocument.addEventListener("load", this.blanks, true);
    this.blanks();
    announcePainted(this.el);
  },
  updated() {
    // A patch re-renders from the server's HTML, which does not carry the ring — the attribute is
    // client state. Re-applying it here is what keeps a selection visible across an unrelated
    // update. The blank floors are client state too.
    this.markSelected?.(this.selectedId, this.selectedAnchor);
    this.placeToolbar?.();
    this.blanks?.();
    announcePainted(this.el);
  },
  destroyed() {
    window.removeEventListener("scroll", this.placeToolbar);
    window.removeEventListener("resize", this.placeToolbar);
    this.el.removeEventListener("dblclick", this.onDblClick);
    this.el.removeEventListener("click", this.onClick);
    this.el.ownerDocument.removeEventListener("click", this.onCapture, true);
    this.el.ownerDocument.removeEventListener("mousedown", this.onPress, true);
    this.el.ownerDocument.removeEventListener("click", this.onLayoutToggle, true);
    this.el.ownerDocument.removeEventListener("click", this.onSelectClick, true);
    this.el.ownerDocument.removeEventListener("contextmenu", this.onContext);
    this.el.removeEventListener("submit", this.onSubmit);
    this.el.removeEventListener("dragstart", this.onDragStart);
    this.el.removeEventListener("dragenter", this.onDragEnter);
    this.el.removeEventListener("dragover", this.onDragOver);
    this.el.removeEventListener("drop", this.onDrop);
    this.el.removeEventListener("dragend", this.onDragEnd);
    this.el.removeEventListener("dragleave", this.onDragLeave);
    this.el.ownerDocument.removeEventListener("dragstart", this.onGripDrag, true);
    this.el.ownerDocument.removeEventListener("dragend", this.onDragEnd, true);
    this.el.ownerDocument.removeEventListener("scroll", this.forgetRects, true);
    window.removeEventListener("keydown", this.onKey);
    window.removeEventListener("pb:dragend", this.onDragAway);
    window.removeEventListener("pb:hints", this.onHints);
    this.el.ownerDocument.removeEventListener("load", this.blanks, true);
    this.indicator?.remove();
  },
};

// A palette card is a drag source. The payload is the same HEEx template click-to-place inserts, so
// both gestures go through one server op and neither can drift from the other.
// A star and a recent row, owned entirely by the browser.
//
// 177 tiles is a lot to scroll past to reach the four you actually use, and which four they are is
// not the site's data — it is one author's habit. So nothing here reaches the server: no event, no
// assign, no re-render of the tile that was starred. The rules live in `pb_prefs.js`, which is
// where they are tested; this only reads the DOM and writes classes.
const PbPalettePrefs = {
  mounted() {
    this.mode = null;

    this.lists = () => ({
      fav: favourites(window.localStorage, this.el.dataset.scope),
      recent: recents(window.localStorage, this.el.dataset.scope),
    });

    // ONE LISTENER, NOT 177. The tiles are re-rendered by every search keystroke and every category
    // change, so anything bound per card would have to be rebound on each patch; delegation from
    // the panel survives all of it.
    this.onClick = (event) => {
      const chip = event.target.closest("[data-pb-prefchip]");
      if (chip) {
        event.preventDefault();
        const next = chip.dataset.pbPrefchip;
        this.mode = this.mode === next ? null : next;
        return this.apply();
      }

      // ONE CHIP AT A TIME. Starred and Recent sit in the same row as the categories and are styled
      // the same, so a row showing two chips lit reads as broken — and the obvious way back to
      // everything, clicking "all", appeared to do nothing at all while a star filter was still on.
      // The category is the server's, the facet is ours; picking a category drops ours.
      if (event.target.closest("[phx-value-cat]")) {
        this.mode = null;
        return this.apply();
      }

      const star = event.target.closest("[data-role='pb-fav']");
      if (star) {
        // The star sits ON the tile, and the tile places the component. Without both of these,
        // starring something places it.
        event.preventDefault();
        event.stopPropagation();
        toggleFavourite(window.localStorage, this.el.dataset.scope, this.nameOf(star));
        return this.apply();
      }

      // Anything else that reaches a tile is an intent to place — click-to-arm and drag both count,
      // and both go through here.
      const cell = event.target.closest("[data-role='pb-compcell']");
      if (cell) this.remember(cell);
    };

    this.onDragStart = (event) => {
      const cell = event.target.closest?.("[data-role='pb-compcell']");
      if (cell) this.remember(cell);
    };

    this.nameOf = (node) => node.closest("[data-role='pb-compcell']")?.dataset.name;

    this.remember = (cell) => {
      noteUse(window.localStorage, this.el.dataset.scope, cell.dataset.name);
      if (this.mode) this.apply();
    };

    this.apply = () => {
      const lists = this.lists();

      for (const chip of this.el.querySelectorAll("[data-pb-prefchip]")) {
        chip.dataset.on = String(chip.dataset.pbPrefchip === this.mode);
      }

      let showing = 0;

      // `style.display`, not the `hidden` attribute: the tile carries Tailwind's `block`, and a
      // class beats the zero-specificity `[hidden]` rule every time — the tile would stay on screen
      // and the filter would look broken.
      for (const cell of this.el.querySelectorAll("[data-role='pb-compcell']")) {
        const name = cell.dataset.name;
        const visible = shows(name, this.mode, lists);

        cell.style.display = visible ? "" : "none";
        if (visible) showing++;

        const star = cell.querySelector("[data-role='pb-fav']");
        if (star) star.dataset.on = String(lists.fav.includes(name));
      }

      // A heading over nothing reads as a section that failed to load, so a group whose every tile
      // is hidden goes with them.
      for (const group of this.el.querySelectorAll("[data-role='pb-comps'] > section")) {
        const alive = [...group.querySelectorAll("[data-role='pb-compcell']")].some(
          (cell) => cell.style.display !== "none",
        );
        group.style.display = alive ? "" : "none";
      }

      // Recency is the whole point of the row — category order is no order at all for "what did I
      // just use". Re-ordered in place rather than re-rendered, so the tiles keep their identity.
      if (this.mode === "recent") this.sortByRecency(lists.recent);

      this.emptyState(showing);
      this.count(showing);
    };

    this.sortByRecency = (recent) => {
      const board = this.el.querySelector("[data-role='pb-comps']");
      if (!board) return;

      const cells = [...this.el.querySelectorAll("[data-role='pb-compcell']")].filter(
        (cell) => cell.style.display !== "none",
      );
      const order = byRecency(
        cells.map((cell) => cell.dataset.name),
        recent,
      );

      for (const name of order) {
        const cell = cells.find((entry) => entry.dataset.name === name);
        if (cell) cell.parentElement.appendChild(cell);
      }
    };

    this.emptyState = (showing) => {
      for (const mode of ["fav", "recent"]) {
        const note = this.el.querySelector(`#pb-palette-empty-${mode}`);
        if (note) note.hidden = !(this.mode === mode && showing === 0);
      }
    };

    // The badge counts what is on screen. Written here rather than by the server, which cannot know
    // — and re-applied on every patch, because the server writes the unfiltered number back.
    this.count = (showing) => {
      const badge = this.el.querySelector("[data-role='pb-count']");
      if (badge) badge.textContent = showing;
    };

    this.el.addEventListener("click", this.onClick, true);
    this.el.addEventListener("dragstart", this.onDragStart, true);
    this.apply();
  },

  // Every search keystroke and category change replaces the tiles, and the fresh ones arrive with
  // no star on them.
  updated() {
    this.apply();
  },

  destroyed() {
    this.el.removeEventListener("click", this.onClick, true);
    this.el.removeEventListener("dragstart", this.onDragStart, true);
  },
};

// The right-click menu, for a canvas node and for a layers row.
//
// It opens with NO round trip: the markup is static, so the hook stamps the node it was opened on
// and pushes the action itself when something is chosen. That matters twice over — a menu that
// waits on the server feels broken, and a patch arriving mid-gesture would otherwise be free to
// replace the row the pointer is resting on.
//
// Both surfaces share one menu component; only the selector and the dataset key differ, and both
// arrive as data attributes.
const PbContextMenu = {
  mounted() {
    const doc = this.el.ownerDocument;
    this.node = null;

    this.close = () => {
      this.el.hidden = true;
      this.node = null;
      this.unwatchFrames();
    };

    // Placed so the whole menu stays on screen: past the right edge it opens leftwards, past the
    // bottom it opens upwards. Measured from the menu's own box rather than assumed, because the
    // rail and the canvas are different widths.
    //
    // A viewport of ZERO is not a tiny viewport — it is a document that has not been laid out (a
    // hidden tab, a headless pane). Flipping against it sends every menu to the top-left corner, so
    // an unknown edge means no flip: the pointer's own position is already right.
    this.open = (x, y) => {
      this.el.hidden = false;

      const box = this.el.getBoundingClientRect();
      const width = doc.documentElement.clientWidth;
      const height = doc.documentElement.clientHeight;

      const left = width && x + box.width > width ? x - box.width : x;
      const top = height && y + box.height > height ? y - box.height : y;

      this.el.style.left = `${Math.max(6, left)}px`;
      this.el.style.top = `${Math.max(6, top)}px`;
      this.watchFrames();
    };

    this.onContext = (event) => {
      const row = event.target.closest?.(this.el.dataset.target);
      if (!row) return this.close();

      event.preventDefault();
      this.node = row.dataset[this.el.dataset.key];
      this.el.dataset.hidden = row.dataset.pbHidden === "true" ? "true" : "false";
      this.open(event.clientX, event.clientY);
    };

    this.mine = (event) => this.el.contains(event.target.closest?.("[data-action]") || event.target);

    // DISMISSED ON POINTERDOWN, chosen on click. Waiting for the click means the menu is still up
    // while the thing under it is already reacting; every menu in every editor closes on the way
    // down. Capture, so a handler that stops the event on its way up cannot leave the menu stranded.
    this.onDown = (event) => {
      if (!this.el.hidden && !this.mine(event)) this.close();
    };

    this.onPick = (event) => {
      const item = event.target.closest?.("[data-action]");
      if (!item || !this.el.contains(item) || !this.node) return;

      this.pushEvent("ctx", { action: item.dataset.action, node_id: this.node });
      this.close();
    };

    this.onKey = (event) => event.key === "Escape" && this.close();

    // THE CANVAS IS A DIFFERENT DOCUMENT. A click in the frame never reaches this one, so a menu
    // opened over the layers rail stayed up while the author carried on working on the page — the
    // one place they are most likely to click next. Same for the three frames of the side-by-side
    // view. Listened to only while the menu is OPEN: a frame can be replaced at any time, and
    // listeners left on a document that has gone are a leak the editor does not need.
    this.watched = [];

    this.watchFrames = () => {
      this.unwatchFrames();

      for (const frame of doc.querySelectorAll("iframe")) {
        const inner = frame.contentDocument;
        if (!inner) continue;

        inner.addEventListener("pointerdown", this.close, true);
        inner.addEventListener("wheel", this.close, true);
        inner.addEventListener("scroll", this.close, true);
        this.watched.push(inner);
      }
    };

    this.unwatchFrames = () => {
      for (const inner of this.watched) {
        inner.removeEventListener("pointerdown", this.close, true);
        inner.removeEventListener("wheel", this.close, true);
        inner.removeEventListener("scroll", this.close, true);
      }

      this.watched = [];
    };

    // The canvas is a frame rendering the SITE's document — it has none of this stylesheet, so its
    // right-clicks come here instead of drawing a second menu of their own. The point arrives in the
    // frame's coordinates and has to be moved into ours, which is what the frame's own box gives.
    //
    // AND SCALED ON THE WAY, because the frame is CSS-zoomed: it keeps its real breakpoint width
    // while being painted smaller, so a 1180px canvas at 30% reports a point up to 1180 wide inside
    // a box 354 wide. Adding the two raw put the menu hundreds of pixels past the pointer, where
    // `open`'s flip then pinned it to a viewport edge. The scale is the painted box over the frame's
    // OWN viewport — the very space the point was measured in — so it is the ratio by definition,
    // with nothing assumed about the style that caused it or how a zoomed element reports its width.
    // A frame with no painted box — never laid out, a hidden tab — is left unscaled: the point on
    // its own is closer than a NaN.
    this.onMessage = (event) => {
      if (!event.data || event.data.pb !== true || event.data.kind !== "context") return;

      const frame = [...doc.querySelectorAll("iframe")].find(
        (candidate) => candidate.contentWindow === event.source,
      );
      if (!frame) return;

      const box = frame.getBoundingClientRect();
      const inner = frame.contentWindow.innerWidth;
      const scale = box.width && inner ? box.width / inner : 1;

      this.node = event.data.id;
      this.el.dataset.hidden = event.data.hidden ? "true" : "false";
      this.open(box.left + event.data.x * scale, box.top + event.data.y * scale);
    };

    doc.addEventListener("contextmenu", this.onContext);
    doc.addEventListener("pointerdown", this.onDown, true);
    doc.addEventListener("click", this.onPick);
    doc.addEventListener("keydown", this.onKey);
    // A menu anchored to a point on screen is wrong the moment the page moves under it.
    doc.addEventListener("scroll", this.close, true);
    window.addEventListener("message", this.onMessage);
    // And a menu is about a page you are still on: leaving takes it with you.
    window.addEventListener("blur", this.close);
  },

  destroyed() {
    const doc = this.el.ownerDocument;

    doc.removeEventListener("contextmenu", this.onContext);
    doc.removeEventListener("pointerdown", this.onDown, true);
    doc.removeEventListener("click", this.onPick);
    doc.removeEventListener("keydown", this.onKey);
    doc.removeEventListener("scroll", this.close, true);
    window.removeEventListener("message", this.onMessage);
    window.removeEventListener("blur", this.close);
    this.unwatchFrames();
  },
};

const PbPaletteItem = {
  mounted() {
    this.onDragStart = (event) => {
      event.dataTransfer.effectAllowed = "copy";
      event.dataTransfer.setData(TEMPLATE_MIME, this.el.dataset.template);
      event.dataTransfer.setData("text/plain", this.el.dataset.template);
      // Asked here, where the template is still readable. The canvas gets the answer through the
      // `phx:pb:drop-hints` listener above; by the time the pointer reaches the frame it has it.
      spreadHints(null);
      // Nothing is being MOVED, so no row of the rail is off limits. Left over from a previous
      // gesture this would have made the rail refuse one arbitrary row for the whole drag.
      window.__pbDragNode = null;
      hintsAwaited = true;
      this.pushEvent("drag_start", { template: this.el.dataset.template });
    };

    // The end of this card's drag is `PbShortcuts`' to announce — it holds the one `dragend`
    // listener this document needs, and it reaches the frames as well as this state.
    this.el.addEventListener("dragstart", this.onDragStart);
  },
  destroyed() {
    this.el.removeEventListener("dragstart", this.onDragStart);
  },
};

// The layers tree reorders with SortableJS — a flat list per level, which is exactly what Sortable
// is good at, and the same hook shape `DashboardGrid` already proves in this app.
// The layers tree is NESTED, so a flat sortable could only ever reorder top-level siblings — which
// is why dragging a row into another row did nothing. This resolves the drop the way the canvas
// does: the top third of a row means "before it", the bottom third "after it", and the middle means
// "inside it" when the row can take children. The server re-checks containment before it moves
// anything, so a wrong guess is refused rather than trusted.
// WHAT A CARD WILL PUT ON THE PAGE, shown while the pointer rests on it.
//
// The hook lives on the PANEL, not on the cards: 151 cards would mean 151 hooks, and the panel is
// the thing that has to survive the palette re-rendering underneath it. Card hovers are caught by
// delegation on the scroll container.
//
// Everything about showing it is client-side and deliberately so — the editor's rule is that hover
// never becomes a round trip. The server is asked exactly once per component: after the pointer has
// settled for DWELL, and never again for a template already in `seen`, so sweeping the palette a
// second time costs nothing at all.
const PbPaletteHover = {
  mounted() {
    // Long enough that crossing the grid on the way to a card lower down opens nothing. A palette is
    // two columns of small targets, so at 380ms a diagonal sweep flashed three previews the reader
    // never asked for; the panel now waits until the pointer has settled.
    const DWELL = 750;
    const MARGIN = 12;
    const DESIGN = 760;
    const SCALE = 0.5;
    const MIN_H = 90;
    const MAX_H = 300;
    const CARD = "[data-role='pb-compcell']";

    this.seen = new Map();
    this.timer = null;
    this.current = null;

    const head = this.el.querySelector("[data-role='pb-card-preview-head']");
    const name = this.el.querySelector("[data-role='pb-card-preview-name']");
    const badgeGlobal = this.el.querySelector("[data-role='pb-card-preview-global']");
    const badgeTenant = this.el.querySelector("[data-role='pb-card-preview-tenant']");
    const note = this.el.querySelector("[data-role='pb-card-preview-note']");
    const frame = this.el.querySelector("[data-role='pb-card-preview-frame']");
    const body = this.el.querySelector("[data-role='pb-card-preview-body']");

    // Laid out at 760px and shown at half that. Transform rather than a narrow viewport: a component
    // that changes shape below its breakpoint would otherwise preview as its mobile self, which is
    // not what dropping it on a desktop page would give you.
    //
    // The panel then takes the HEIGHT of what was drawn, because a fixed box is wrong in both
    // directions — an alert leaves three quarters of it empty, and a pricing table is cut off. The
    // frame is same-origin so its height can simply be read; it cannot run scripts (no
    // `allow-scripts`), so there is nothing inside it that could use that.
    const fit = () => {
      const height = Math.min(MAX_H, Math.max(MIN_H, Math.ceil(drawnHeight() * SCALE)));

      frame.style.height = `${Math.ceil(height / SCALE)}px`;
      body.style.height = `${height}px`;
    };

    // MEASURED WITH THE FRAME COLLAPSED, which is the whole trick: an iframe's body stretches to the
    // iframe, so asking a full-height frame how tall its content is answers with the frame's own
    // height. Collapse it first and `scrollHeight` is the content again.
    const drawnHeight = () => {
      frame.style.width = `${DESIGN}px`;
      frame.style.transform = `scale(${SCALE})`;
      frame.style.height = "0px";

      try {
        const doc = frame.contentDocument;
        return (doc && doc.body && doc.body.scrollHeight) || MIN_H / SCALE;
      } catch (_opaque) {
        return MIN_H / SCALE;
      }
    };

    // Empty of everything a person could see: no words, nothing drawn, and no picture or icon that
    // would have height of its own. An empty box is indistinguishable from a preview that failed,
    // so it is worth one measurement to say which it is.
    const blank = () => {
      try {
        const doc = frame.contentDocument;
        if (!doc || !doc.body) return false;
        if (doc.body.innerText.trim() !== "") return false;
        if (doc.body.querySelector("img,svg,video,canvas,iframe,input,select,textarea,hr")) {
          return false;
        }

        // Above this it is a box with real size — a spacer or a panel — and showing it is fair. The
        // empty containers this catches come out at the height of their own padding.
        return drawnHeight() < 48;
      } catch (_opaque) {
        return false;
      }
    };

    const place = (card) => {
      const box = card.getBoundingClientRect();
      const panel = this.el.getBoundingClientRect();
      const top = Math.min(
        Math.max(MARGIN, box.top + box.height / 2 - panel.height / 2),
        window.innerHeight - panel.height - MARGIN
      );

      // Beside the palette, and on whichever side has room — a right-hand rail on a narrow window
      // would otherwise push it off screen.
      const right = box.right + MARGIN;
      const left = right + panel.width < window.innerWidth - MARGIN ? right : box.left - panel.width - MARGIN;

      this.el.style.top = `${Math.max(MARGIN, top)}px`;
      this.el.style.left = `${Math.max(MARGIN, left)}px`;
    };

    const draw = (card, entry) => {
      if (entry && entry.html) {
        note.textContent = "";
        frame.srcdoc = entry.html;

        // Sized and shown only once the markup is really there: measuring a frame mid-parse gives
        // the empty document's height, and the panel would settle to its minimum and then jump.
        frame.onload = () => {
          // A COMPONENT THAT DRAWS NOTHING SAYS SO. A flash group with no flashes in it, a list with
          // no items — these render to an empty box, and an empty box is indistinguishable from a
          // preview that failed. Saying which it is costs one measurement.
          if (blank()) {
            frame.removeAttribute("srcdoc");
            frame.style.opacity = "0";
            body.style.height = `${MIN_H}px`;
            note.textContent = "Nothing to show until this has content of its own.";
            place(card);
            return;
          }

          fit();
          place(card);
          frame.style.opacity = "1";
        };
      } else {
        frame.removeAttribute("srcdoc");
        frame.style.opacity = "0";
        body.style.height = `${MIN_H}px`;
        note.textContent = (entry && entry.note) || "Drawing…";
        place(card);
      }
    };

    // The card's own words lead, with the component's real name behind them, because the palette
    // labels a card `Overlay` and the thing a template names is `chelekom-overlay` — an author
    // reading a preview wants the first and an author writing HEEx wants the second.
    //
    // The scope badge is here because it used to be in the native tooltip, and that tooltip is gone:
    // two floating layers for one hover is one too many. Both badges are in the markup so their
    // colours stay in the template rather than being rebuilt from strings in here.
    const show = (card, entry) => {
      const global = card.dataset.scope !== "tenant";

      head.textContent = card.dataset.label || card.dataset.name || "";
      name.textContent = card.dataset.name || "";
      badgeGlobal.hidden = !global;
      badgeTenant.hidden = global;

      this.el.hidden = false;
      draw(card, entry);
    };

    const hide = () => {
      clearTimeout(this.timer);
      this.timer = null;
      this.current = null;
      this.card = null;
      this.el.hidden = true;
      frame.removeAttribute("srcdoc");
      frame.style.opacity = "0";
    };

    this.onOver = (event) => {
      const card = event.target.closest(CARD);
      if (!card) return;

      const button = card.querySelector("[data-template]");
      const template = button && button.dataset.template;
      if (!template) return;
      if (this.current === template) return;

      clearTimeout(this.timer);
      this.current = template;

      this.timer = setTimeout(() => {
        if (this.current !== template) return;

        const entry = this.seen.get(template);
        this.card = card;
        show(card, entry);

        // ASKED ONCE. A component already rendered this session is drawn from `seen`, so moving back
        // along a row of cards sends nothing.
        if (!entry) this.pushEvent("preview_card", { template });
      }, DWELL);
    };

    this.onOut = (event) => {
      const card = event.target.closest(CARD);
      if (!card) return;
      if (event.relatedTarget && event.relatedTarget.closest(CARD) === card) return;
      hide();
    };

    // A DRAG IS NOT A HOVER. The moment a card is picked up the preview is in the way of the thing
    // it was describing, and it must not reappear while the pointer crosses other cards.
    this.onDrag = () => hide();

    this.onArrive = ({ detail }) => {
      if (!detail || !detail.template) return;

      this.seen.set(detail.template, { html: detail.html, note: detail.note });
      if (this.current !== detail.template || this.el.hidden) return;

      const card = this.card;
      if (card) draw(card, this.seen.get(detail.template));
    };

    this.palette = document.querySelector("[data-role='pb-comps']");
    if (this.palette) {
      this.palette.addEventListener("mouseover", this.onOver);
      this.palette.addEventListener("mouseout", this.onOut);
      this.palette.addEventListener("scroll", this.onDrag, { passive: true });
    }

    window.addEventListener("dragstart", this.onDrag, true);
    window.addEventListener("phx:pb:card-preview", this.onArrive);
  },
  destroyed() {
    clearTimeout(this.timer);

    if (this.palette) {
      this.palette.removeEventListener("mouseover", this.onOver);
      this.palette.removeEventListener("mouseout", this.onOut);
      this.palette.removeEventListener("scroll", this.onDrag);
    }

    window.removeEventListener("dragstart", this.onDrag, true);
    window.removeEventListener("phx:pb:card-preview", this.onArrive);
  },
};

const PbLayers = {
  // The selected row is brought into view on every patch, smoothly and only when it is actually off
  // screen: a tree of a few hundred rows is unreadable if selecting on the canvas leaves the rail
  // wherever it happened to be, and a scroll that fires when the row is already visible is worse.
  // Pushed by the server whenever the selection moves, rather than watched here: the rail is patched
  // row by row and the hook's own `updated()` does not reliably fire for a change deep inside it,
  // which is why selecting on the canvas used to leave the rail wherever it happened to be. A frame's
  // grace covers the relayout when the same patch also opened a branch.
  mounted() {
    const ROW = "[data-layer-row]";

    const ROOT_DROP = "[data-role='pb-root-drop']";

    // NOTHING IN THIS RAIL MOVES WHILE A DRAG IS IN FLIGHT.
    //
    // The first version of this drew a "drop inside …" strip under the row the pointer was on, and
    // that is a reflow: showing one is harmless, since it only moves what is BELOW its own row, but
    // HIDING the previous one moves the row now under the pointer, and the strip was taller than a
    // row. Every downward row-to-row step therefore pulled the new row up past the pointer and the
    // line jumped from "before footer" to "inside footer" with the pointer standing still; reaching
    // the end-of-page target moved it out from under the pointer altogether, which is a release that
    // fires no `drop` event and says nothing.
    //
    // So the only things written here are attributes on boxes that already have their size: the
    // marker (`data-drop`), which the row draws as a border edge, a tint and a chip, and the map
    // (`data-can`), which it draws as an outline. Both are free.
    const clear = () => {
      const was = this.marked;
      this.marked = null;
      this.el.querySelectorAll("[data-drop]").forEach((el) => el.removeAttribute("data-drop"));

      // The marked row gives up its "could take this" outline while it is the actual target — two
      // treatments on one row is one too many, and the border is the more specific of them.
      if (was && this.markedCan) was.setAttribute("data-can", "true");
      this.markedCan = false;
    };

    // WHERE THIS DRAG COULD GO, painted once for the whole gesture rather than per pointer move.
    //
    // The verdict is the server's and arrives once (see `EditorSession.drop_hints/2`); until then
    // the rail falls back to `data-container`, which is `Containment` answered about the target
    // alone, so it says yes to rows this particular node cannot enter. That is why the sweep runs
    // again when the hints land: the second pass takes back the rows the server refused.
    const paintAccepts = () => {
      const hints = window.__pbDropHints;
      const dragged = draggingId();

      this.witness = null;

      this.el.querySelectorAll(ROW).forEach((row) => {
        const id = row.dataset.layerRow;
        const takes = hints ? hints[id] === true : row.dataset.container === "true";

        if (takes && id !== dragged) {
          row.setAttribute("data-can", "true");
          this.witness = this.witness || row;
        } else {
          row.removeAttribute("data-can");
        }
      });

      this.painted = hints ? "verdict" : "guess";
    };

    const unpaint = () => {
      this.painted = null;
      this.witness = null;
      this.el.querySelectorAll("[data-can]").forEach((el) => el.removeAttribute("data-can"));
    };

    // IS THE MAP STILL THERE? `data-can` is written here and is in nothing the server renders, so any
    // patch that touches a row takes it straight off again — a branch springing open, an autosave, a
    // collaborator's edit, presence. Believing our own `painted` flag left the whole map gone for the
    // rest of the gesture, on a rail the author is still trying to read.
    //
    // One row is kept as the witness rather than counting them all, because this is asked on every
    // pointer move and the repaint it guards is a sweep of the entire rail.
    const mapStanding = () =>
      !!this.painted &&
      (!this.witness || (this.witness.isConnected && this.witness.dataset.can === "true"));

    // Re-painted when the verdict arrives, and only then: `dragover` fires on every pointer move and
    // this is a sweep of the whole rail.
    const repaintIfAnswered = () => {
      if (this.painted === "guess" && window.__pbDropHints) paintAccepts();
    };

    // A ROW OPENS WHEN YOU REST ON IT, so a drag can reach what is shut underneath.
    //
    // `default_expanded/1` opens the roots and one level below them and nothing else, so a tree of
    // any depth is mostly shut — a `<span>` four levels inside a `<p>` inside a `<div>` has no row
    // to aim at at all. The only way to reach it was to let go of what you were holding, click your
    // way down, and pick it up again, which is not a way to reach it.
    //
    // Opening is the SERVER's business: a shut branch is not in this document, so there is nothing
    // to reveal here and `toggle_expand` is the only way to get it. That makes this the one hover in
    // the editor that is allowed a round trip, and the dwell is what earns it — long enough that
    // crossing a row on the way somewhere else opens nothing.
    //
    // It does not shift what the pointer is on. Children are rendered AFTER their row, so opening
    // one moves only what is below it — the same property the drop marker relies on, and the reason
    // this is safe mid-drag when revealing a strip above the pointer was not.
    //
    // Nothing is closed again. Closing on the way out would move rows while the pointer is between
    // them, and a branch opened to drop into must still be open to see the drop land in it.
    const SPRING = 600;

    const stopSpring = () => {
      clearTimeout(this.spring);
      this.spring = null;
      this.springing = null;
    };

    const springOpen = (row) => {
      const id = row && row.dataset.open === "false" ? row.dataset.layerRow : null;
      if (this.springing === id) return;

      stopSpring();
      if (!id || id === draggingId()) return;

      this.springing = id;
      this.spring = setTimeout(() => {
        // Read again rather than trusting the row captured 600ms ago: a patch may have opened it,
        // and `toggle_expand` TOGGLES — asking twice would shut the branch instead.
        const still = this.el.querySelector(`[data-layer-row="${CSS.escape(id)}"]`);
        if (!still || still.dataset.open !== "false") return;

        // THE MAP IS REDRAWN AS THE BRANCH LANDS, not on the next pointer move. The patch that opens
        // it takes `data-can` off every row it touches — the attribute is written here and is in
        // nothing the server renders — and the rows that arrive with it were rendered after the
        // sweep, so they carry none of it either. Waiting for the pointer to move would blink the
        // whole map off at the exact moment the author is reading it to decide where to go next.
        //
        // A frame after the reply, because the reply and the diff are separate messages and only the
        // frame boundary guarantees the new rows are in the document. `painted` is null once the
        // gesture is over, which is what stops a late reply repainting a rail nobody is dragging on.
        this.pushEvent("toggle_expand", { id }, () => {
          if (this.painted) requestAnimationFrame(paintAccepts);
        });
      }, SPRING);
    };

    // AND THE RAIL SCROLLS AT ITS EDGES, which it never did. HTML drag does not scroll for you and
    // there is no way to let go and grab again mid-gesture, so a target below the fold could not be
    // reached — and a branch that has just sprung open is very often below the fold, because it just
    // pushed itself there. `edgeVelocity` is the canvas's, unchanged: speed rises as the pointer
    // nears the edge, so a nudge creeps and a push moves.
    let scrollBy = 0;
    let scrolling = null;

    const runScroll = () => {
      if (!scrollBy) return (scrolling = null);
      this.el.scrollTop += scrollBy;
      scrolling = requestAnimationFrame(runScroll);
    };

    const edgeScroll = (event) => {
      const box = this.el.getBoundingClientRect();

      // The canvas's 56px edge is a fraction of a full-height document; the rail is a panel, and on
      // a short one — a narrow window, the assistant sheet open beside it — 56px at each end is the
      // whole thing, so resting anywhere in it would scroll. Never more than a quarter per side.
      const edge = Math.min(56, box.height / 4);

      scrollBy = edgeVelocity(event.clientY - box.top, box.height, { edge });
      if (scrollBy && !scrolling) scrolling = requestAnimationFrame(runScroll);
    };

    const stopScroll = () => {
      scrollBy = 0;
      if (scrolling) cancelAnimationFrame(scrolling);
      scrolling = null;
    };

    // The end-of-page target is LAST in the rail, so showing it moves nothing above it — it is the
    // one box here whose size may change, and it can only push the rail's own bottom padding down.
    const tail = () => this.el.querySelector(ROOT_DROP);

    const showTail = (show) => {
      const el = tail();
      if (!el) return;
      if ((el.dataset.show === "true") === show) return;

      if (show) el.dataset.show = "true";
      else delete el.dataset.show;
    };

    // Nothing under the pointer is a target. Not the end of the gesture — the pointer is free to
    // come back, so the map stays painted and the rail keeps scrolling at its edges.
    const rest = () => {
      stopSpring();
      clear();
    };

    // The gesture is over, however it ended. `dragend` fires on the SOURCE, which for a palette card
    // and for a canvas node is not in this rail at all, so this is also reachable from `window` and
    // from the canvas's own message.
    const finish = () => {
      this.dragging = null;
      spreadHints(null);
      window.__pbDragNode = null;
      stopSpring();
      stopScroll();
      clear();
      unpaint();
      showTail(false);
    };

    // ⌘-CLICK HOLDS A SECOND ROW, the same as on the canvas. Every row's name is a `phx-click`
    // that SELECTS, which would throw away whatever was being held, so the modified click is
    // caught before it reaches the button and re-sent as a mark.
    this.onModifiedClick = (event) => {
      if (!event.metaKey && !event.ctrlKey) return;

      const row = event.target.closest(ROW);
      if (!row) return;

      event.preventDefault();
      event.stopPropagation();
      this.pushEvent("mark", { id: row.dataset.layerRow });
    };

    this.el.addEventListener("click", this.onModifiedClick, true);

    // THE OTHER HALF OF `pb:reveal-layer`. `BuilderLive.expand_selected/2` has always pushed this
    // whenever the selection moved, and nothing was listening — so selecting on the canvas marked
    // the row and left the rail wherever it happened to be, exactly as the comment above says it
    // must not. The event carries the id because the rail is patched row by row and `updated()` does
    // not reliably fire for an attribute deep inside it.
    this.handleEvent("pb:reveal-layer", ({ id }) => {
      if (!id) return;

      // A FRAME'S GRACE. The same patch often opens the branch this row is in, and measuring before
      // that relayout lands reads the row's old box — usually zero-height, which scrolls to the
      // wrong place or not at all.
      requestAnimationFrame(() => {
        const row = this.el.querySelector(`[data-layer-row="${CSS.escape(id)}"]`);
        if (!row) return;

        // THE ELEMENT THAT ACTUALLY SCROLLS, which is not always this one. The hook sits on the rail
        // because that is where the rows are, but which box carries the overflow depends on how tall
        // the panel is and what the layout above it does — and setting `scrollTop` on a box that does
        // not scroll silently does nothing at all, which is the failure this whole handler exists to
        // stop. So it is asked for rather than assumed: climb from the row until a box is found that
        // both allows overflow and actually has some.
        const scroller = (() => {
          let el = row.parentElement;

          while (el && el !== document.body) {
            const overflow = getComputedStyle(el).overflowY;
            const scrolls = overflow === "auto" || overflow === "scroll";
            if (scrolls && el.scrollHeight > el.clientHeight) return el;
            el = el.parentElement;
          }

          return this.el;
        })();

        // ONLY WHEN IT IS ACTUALLY OFF SCREEN. Scrolling a row that is already in view is motion the
        // reader did not ask for, and on every selection it reads as the rail twitching.
        const railBox = scroller.getBoundingClientRect();
        const rowBox = row.getBoundingClientRect();
        if (rowBox.top >= railBox.top && rowBox.bottom <= railBox.bottom) return;

        // THE RAIL IS SCROLLED DIRECTLY, not through `scrollIntoView`. That call walks up and moves
        // EVERY scrollport it finds on the way, so it also drags whatever the panel is sitting in;
        // and its smooth mode is an animation the next LiveView patch cancels outright — which is
        // precisely when this runs, because selecting is what patched the rail in the first place.
        // Setting one container's own offset cannot be cancelled and cannot move anything else.
        //
        // Centred rather than `block: "nearest"`. Nearest moves the minimum, so a row reached from
        // far away lands hard against an edge with no sight of what it sits among; the point of
        // revealing it is to be able to read where it is.
        const still =
          document.hidden || window.matchMedia("(prefers-reduced-motion: reduce)").matches;

        const centred =
          scroller.scrollTop + (rowBox.top - railBox.top) - (scroller.clientHeight - rowBox.height) / 2;

        scroller.scrollTo({ top: Math.max(0, centred), behavior: still ? "auto" : "smooth" });
      });
    });

    // A slot belongs to its component and only makes sense among its siblings, so it can be reordered
    // but never dropped INSIDE another slot. Everything else may go inside one — a component in a
    // slot is the whole point of slots.
    //
    // `window.__pbDropHints` is the server's verdict for this drag, asked for once at dragstart (see
    // `EditorSession.drop_hints/2`). Without it the rail would offer "inside" for any row the markup
    // calls a container, including the `<span>` a section cannot go into.
    // THE HINT OVERRULES THE MARKUP, and only stands in for it until the hint arrives. `data-container`
    // is `drop_target?/2`'s guess made while the row was rendered, before anything was picked up, and
    // it used to be an EXTRA veto on top of the server's verdict — a row could be told yes by
    // `Containment` and still refuse, which is what stopped a field being dropped into the `<.form>`
    // the editor puts around every loose field: that form has no palette row, so `drop_target?/2`
    // answered "no slots" for a component Phoenix itself declares one for, and the middle band of the
    // row degraded to "after". The field landed beside the form instead of in it, every time.
    //
    // The canvas has always read them in this order (`nests` in `PbCanvas`); the rail now agrees.
    //
    // A slot belongs to its component and only makes sense among its siblings, so it can be reordered
    // but never dropped INSIDE another slot. Everything else may go inside one — a component in a
    // slot is the whole point of slots. A drag that began on the canvas has no row in this rail to
    // read a kind off, and a node the rail cannot see is not a slot it needs to protect.
    // WHICH NODE IS IN FLIGHT, wherever the gesture began. `this.dragging` is only ever set by this
    // rail's own `dragstart`; a node picked up on the CANVAS starts in the iframe, and its id cannot
    // be read off the dataTransfer until `drop` — the values are sealed for the whole gesture. So
    // the canvas posts it up as it starts (see `toParent` in `PbCanvas`) and this is where the two
    // answers meet. Without it the rail offered the dragged node's own row as a place to drop it.
    const draggingId = () => this.dragging || window.__pbDragNode || null;

    // WHAT THIS GESTURE IS CARRYING. Two questions, deliberately separate: whether the rail should
    // take it at all, and whether taking it is a MOVE or a COPY. The second one is not cosmetic —
    // HTML resolves a `dropEffect` the source did not allow to `none`, and a `none` drop is
    // discarded silently, with no `drop` event to notice. Answering "move" to the palette's "copy"
    // is exactly why a card could never be dropped on the tree.
    const ours = (event) => {
      if (this.dragging) return true;
      const types = [...(event.dataTransfer?.types || [])];
      return types.includes(NODE_MIME) || types.includes(TEMPLATE_MIME);
    };

    const isMove = (event) =>
      !!this.dragging || [...(event.dataTransfer?.types || [])].includes(NODE_MIME);

    const nests = (row) => {
      const hints = window.__pbDropHints;
      if (hints) {
        if (hints[row.dataset.layerRow] !== true) return false;
      } else if (row.dataset.container !== "true") {
        return false;
      }

      const id = draggingId();
      const dragged = id && this.el.querySelector(`[data-layer-row="${CSS.escape(id)}"]`);
      return !(dragged?.dataset.kind === "slot" && row.dataset.kind === "slot");
    };

    // HALF THE ROW MEANS INSIDE, on a row that can be entered.
    //
    // It was the middle 40% — twelve pixels of a 31px row, and for a component with nineteen
    // properties and a parsed template under it, about one per cent of what the thing occupies in
    // the rail. The report was the plain truth: "so much property and etc listed instead of under
    // something". Beside is still reachable at eight pixels a side, which is the band every other
    // tree editor gives it, and the outer quarters are where the pointer naturally lands when the
    // intent really is "between these two".
    const offsetIn = (row, event) => {
      const box = row.getBoundingClientRect();
      return (event.clientY - box.top) / box.height;
    };

    const zoneOf = (row, event) => {
      const offset = offsetIn(row, event);
      if (offset < 0.25) return "before";
      if (offset > 0.75) return "after";

      // A row that cannot be entered splits its middle rather than giving all of it to "after" —
      // the pointer is in the top half, and "before" is what the top half has meant everywhere else.
      return nests(row) ? "inside" : offset < 0.5 ? "before" : "after";
    };

    this.onDragStart = (event) => {
      const row = event.target.closest(ROW);
      if (!row) return;
      this.dragging = row.dataset.layerRow;
      spreadHints(null);
      window.__pbDragNode = null;
      showTail(true);
      paintAccepts();
      event.dataTransfer.effectAllowed = "move";
      // Firefox will not start a drag without payload.
      event.dataTransfer.setData("text/plain", this.dragging);
      // What lets this row be dropped on the CANVAS, which cannot see this hook's state — see
      // `NODE_MIME` at the top of the file.
      event.dataTransfer.setData(NODE_MIME, this.dragging);
      hintsAwaited = true;
      this.pushEvent("drag_start", { node_id: this.dragging });
    };

    const accepts = (id) => {
      const hints = window.__pbDropHints;
      return !hints || !id || id === "root" || hints[id] !== false;
    };

    // Beside a row means inside that row's PARENT, so when the parent cannot hold this the answer is
    // the same one the canvas gives: climb, and land after the branch it could not enter. Without it
    // the rail marks a line the server would only have to relocate.
    const resolve = (row, event) => {
      const zone = zoneOf(row, event);
      if (zone === "inside") return { row, zone };

      let target = row;
      let landing = zone;

      while (!accepts(target.dataset.parentId)) {
        const up = this.el.querySelector(`[data-layer-row="${CSS.escape(target.dataset.parentId)}"]`);
        if (!up) break;
        target = up;
        landing = "after";
      }

      return { row: target, zone: landing };
    };

    const allow = (event) => {
      event.preventDefault();
      event.dataTransfer.dropEffect = isMove(event) ? "move" : "copy";
    };

    // THE ROW THE POINTER IS ON, or the row whose details it is on. Between a component's row and its
    // slots the rail draws the component's `.properties`, `.slots` and `.markup` groups, and on a
    // navbar that is most of what sits between it and the next row: a drop there was no drop at all,
    // so dragging a section to just under the navbar did nothing and said nothing. Those groups
    // belong to the component, so they answer as its row — and the pointer is below that row's own
    // box, which `zoneOf` already reads as "after": the node lands after the component, the way the
    // marker on the component's row says.
    const rowUnder = (target) => {
      const row = target.closest(ROW);
      if (row) return row;

      const owner = target.closest("[data-layer-id]");
      return (owner && this.el.contains(owner) && owner.querySelector(`:scope > ${ROW}`)) || null;
    };

    this.onDragOver = (event) => {
      if (!ours(event)) return rest();

      // The rail has been entered, so the end-of-page target and the map of what will take this are
      // worth drawing for the rest of the gesture. `dragenter` alone would miss a drag that began on
      // a row of this very rail, and a drag that began anywhere else fires no `dragstart` here.
      showTail(true);
      edgeScroll(event);
      if (mapStanding()) repaintIfAnswered();
      else paintAccepts();

      const end = event.target.closest(ROOT_DROP);
      if (end) {
        allow(event);
        if (this.marked === end) return;
        clear();
        end.setAttribute("data-drop", "inside");
        this.marked = end;
        return;
      }

      const over = rowUnder(event.target);

      // A HIGHLIGHT THAT OUTLIVES THE TARGET IS A LIE, and this one was told constantly. Between a
      // component's row and its children the rail draws its properties group, its parsed markup and
      // its slot ghosts — for a `chelekom-modal`, about thirty-four rows. Drifting a few pixels down
      // onto one of them left this handler through the early return WITHOUT clearing, so the row
      // above kept its blue "inside" border while the browser had gone back to refusing the drop.
      // Those rows answer as their component's now (`rowUnder`), with the marker moved to "after";
      // what is left with no row at all still clears, because no `drop` event is fired when the
      // last `dragover` was not cancelled and there would be nothing to report.
      if (!over || over.dataset.layerRow === draggingId()) return rest();

      // Whatever the pointer is resting on, including a row it is only aiming BESIDE: `<ul>` refuses
      // a paragraph and the `<li>` inside it takes one, so a row this drag cannot enter is still
      // worth opening.
      springOpen(over);
      allow(event);

      const { row, zone } = resolve(over, event);
      if (this.marked === row && row.dataset.drop === zone) return;

      clear();

      // The marked row gives up its map outline while it IS the target. Two dashed treatments on one
      // row read as two different offers; `clear()` puts it back when the pointer moves on.
      this.markedCan = row.dataset.can === "true";
      row.removeAttribute("data-can");
      row.setAttribute("data-drop", zone);
      this.marked = row;
    };

    // INSIDE MEANS LAST, not first. The canvas has always sent `9999` for it and `Tree`'s own
    // `clamp/2` reads any index past the end as "append" — the rail sending `0` put a node dropped
    // onto the middle of a row in front of everything already there, so dropping a field onto a
    // form wrapper landed it above the fields that were there before it.
    const landingFor = (row, zone) => {
      const index = Number(row.dataset.index || 0);

      return zone === "inside"
        ? { parent_id: row.dataset.layerRow, index: 9999 }
        : { parent_id: row.dataset.parentId, index: zone === "before" ? index : index + 1 };
    };

    this.onDrop = (event) => {
      // WHAT IS BEING DROPPED, read in the one place it is legible. A node's id and a palette card's
      // template are both sealed until now; a node is a MOVE and a card is an INSERT, and the server
      // tells them apart by whether `node_id` is on the payload — see `EditorSession.drop_kind/1`.
      const node = this.dragging || event.dataTransfer.getData(NODE_MIME);
      const template = node ? "" : event.dataTransfer.getData(TEMPLATE_MIME);
      if (!node && !template) return finish();

      const end = event.target.closest(ROOT_DROP);
      const over = end ? null : rowUnder(event.target);
      if (!end && (!over || over.dataset.layerRow === node)) return finish();

      const { row, zone } = end ? {} : resolve(over, event);
      const landing = end ? { parent_id: "root", index: 9999 } : landingFor(row, zone);

      // BEFORE THE VERDICT, "inside" is the markup's guess. A row the server then refuses is a drop
      // beside it, in front from its top half, as `zoneOf` splits a row that cannot be entered — so
      // the server's fallback is told which half (`Placement.beside/4`).
      if (zone === "inside") landing.fallback_before = offsetIn(row, event) < 0.5;

      event.preventDefault();
      this.pushEvent("drop", node ? { node_id: node, ...landing } : { template, ...landing });
      finish();
    };

    // `dragend` fires on the SOURCE of the gesture, and for two of the three surfaces that is not in
    // this rail: a palette card is elsewhere in this document, and a canvas node is in the iframe.
    // Bound on `window` for the first, reached through `pb:dragend` for the second — without both,
    // a card picked up and dropped somewhere else left the rail's strips standing open.
    this.onDragEnd = () => finish();

    // `dragleave` bubbles out of every row the pointer crosses, so clearing on all of them made the
    // marker blink for the whole drag. Only leaving the rail itself clears it.
    //
    // The end-of-page target stays open. The pointer that just left is on its way to the canvas and
    // may well come back, and closing it costs the rail its own height twice for nothing.
    this.onDragLeave = (event) => {
      if (event.relatedTarget && this.el.contains(event.relatedTarget)) return;
      stopScroll();
      rest();
    };

    this.el.addEventListener("dragstart", this.onDragStart);
    // Entering a row has to be accepted as well, or a drop that lands in the same motion that
    // crossed into it is discarded — the same rule the canvas needs.
    this.el.addEventListener("dragenter", this.onDragOver);
    this.el.addEventListener("dragover", this.onDragOver);
    this.el.addEventListener("drop", this.onDrop);
    this.el.addEventListener("dragleave", this.onDragLeave);
    window.addEventListener("dragend", this.onDragEnd, true);
    window.addEventListener("pb:dragend", this.onDragEnd);
  },
  destroyed() {
    this.el.removeEventListener("click", this.onModifiedClick, true);
    this.el.removeEventListener("dragstart", this.onDragStart);
    this.el.removeEventListener("dragenter", this.onDragOver);
    this.el.removeEventListener("dragover", this.onDragOver);
    this.el.removeEventListener("drop", this.onDrop);
    this.el.removeEventListener("dragleave", this.onDragLeave);
    window.removeEventListener("dragend", this.onDragEnd, true);
    window.removeEventListener("pb:dragend", this.onDragEnd);
    // A pending spring would ask a LiveView that is gone to open a row that is gone.
    clearTimeout(this.spring);
  },
};

// THE FRAME IS BUSY, AND THE PAGE SAYS SO WHILE IT IS.
//
// One overlay covers both moments a canvas frame is not showing what was asked for: the FIRST load,
// where there is nothing underneath yet, and every LIVE swap after it — opening a draft, reverting a
// version — where the frame never navigates and no `load` event ever fires again.
//
// It was two, and they answered the same question differently: the first with a bare spinner and no
// way to tell a slow render from a dead one, the second with a label and a running clock.
//
// State is module-level rather than per-hook because the breakpoint view has SIX frames all showing
// the same document: one load, or one swap, covers all of them and each has its own overlay.
const PB_FRAME_BUSY = {
  since: 0,
  revision: null,
  timer: null,
  deadline: null,
  detail: null,
  stages: [],

  overlays() {
    return document.querySelectorAll("[data-role='pb-frame-busy']");
  },

  // WHAT A LONG WAIT IS TOLD. There is no percentage to report — the server does not know how far
  // through a render it is — so the honest escalation is to say more as more time passes and to stop
  // implying that the usual wait is what is happening. Silence past ten seconds reads as a hang, and
  // a spinner that has not changed in a minute reads as a bug.
  stagesFor(label) {
    return [
      { after: 0, text: label },
      { after: 6000, text: "Still working — this document is a large one." },
      { after: 15000, text: "Taking longer than usual. The server has not answered yet." },
      { after: 40000, text: "Still waiting. Nothing has failed, but something is very slow." },
    ];
  },

  start(label, revision, { settleOnLoad = false } = {}) {
    this.revision = revision === undefined ? null : String(revision);
    this.stages = this.stagesFor(label || "Loading…");
    this.since = Date.now();

    for (const overlay of this.overlays()) {
      overlay.hidden = false;
      const detail = overlay.querySelector("[data-role='pb-busy-detail']");
      if (detail) detail.hidden = true;
    }

    // HELD BACK FOR HALF A SECOND. A load that finishes quickly would otherwise flash a sentence and
    // a clock at somebody with no time to read either, which reads as a glitch rather than as
    // progress. The spinner is up from the first frame; the words arrive only if there is a wait
    // worth explaining.
    clearTimeout(this.detail);
    this.detail = setTimeout(() => this.reveal(), 500);

    this.tick();
    clearInterval(this.timer);
    this.timer = setInterval(() => this.tick(), 200);

    // A LOST SIGNAL MUST NOT LEAVE THE EDITOR COVERED — but only where there is something worth
    // uncovering. On a swap the old document is still underneath, so giving up after fifteen seconds
    // shows the reader something real. On a FIRST load there is nothing under the overlay but a
    // blank iframe, and pulling it away to reveal a white void turns a slow load into what looks
    // like a broken one. There it waits, and says so in stronger words as it goes.
    clearTimeout(this.deadline);
    this.deadline = settleOnLoad ? null : setTimeout(() => this.stop(), 15000);
  },

  // The overlay the SERVER rendered already covering, on the first load. Nothing pushed it, so
  // nothing would have started its clock or armed its listeners.
  adopt() {
    const covering = [...this.overlays()].filter((overlay) => !overlay.hidden);
    if (!covering.length) return;

    const label = covering[0].querySelector("[data-role='pb-busy-label']");
    this.start(label ? label.textContent.trim() : "Loading the canvas…", null, {
      settleOnLoad: true,
    });

    // `load` means the iframe's DOCUMENT arrived, which on a first load is the tree already
    // server-rendered into that response — so the reader is looking at the page. The canvas also
    // posts `painted` once its own socket connects. Whichever happens first is the answer; neither
    // alone is, which is why the old split between them was wrong.
    for (const overlay of covering) {
      const frame = document.getElementById(overlay.dataset.frame || "");
      if (!frame || frame.__pbBusyWatched) continue;

      frame.__pbBusyWatched = true;
      const done = () => this.stop();
      frame.addEventListener("load", done, { once: true });
      frame.addEventListener("error", done, { once: true });
    }
  },

  reveal() {
    for (const overlay of this.overlays()) {
      const detail = overlay.querySelector("[data-role='pb-busy-detail']");
      if (detail && !overlay.hidden) detail.hidden = false;
    }
  },

  // Only a revision at least as new as the one asked for settles it. Without the comparison, the
  // patch that CARRIED the request — the editor's own re-render, which the frame answers first —
  // took the overlay down before the document had changed.
  settle(revision) {
    if (!this.since) return;
    if (this.revision !== null && Number(revision) < Number(this.revision)) return;
    this.stop();
  },

  stop() {
    clearInterval(this.timer);
    clearTimeout(this.deadline);
    clearTimeout(this.detail);
    this.timer = null;
    this.deadline = null;
    this.detail = null;
    this.since = 0;
    this.revision = null;
    for (const overlay of this.overlays()) overlay.hidden = true;
  },

  tick() {
    const waited = Date.now() - this.since;
    const seconds = (waited / 1000).toFixed(1);
    const stage = this.stages.filter((entry) => waited >= entry.after).pop();

    for (const overlay of this.overlays()) {
      if (overlay.hidden) continue;

      const elapsed = overlay.querySelector("[data-role='pb-busy-elapsed']");
      const label = overlay.querySelector("[data-role='pb-busy-label']");
      if (elapsed) elapsed.textContent = `${seconds}s`;
      if (label && stage && stage.text) label.textContent = stage.text;
    }
  },
};

// Mounted on the frame column, so the editor can raise the overlay from the server on the same round
// trip that swaps the document — and so the one the server rendered already covering, for the first
// load, gets its clock started and its listeners armed.
const PbFrameBusy = {
  mounted() {
    this.handleEvent("pb:frame-busy", ({ label, revision }) =>
      PB_FRAME_BUSY.start(label || "Loading…", revision),
    );

    // BOTH ENDS IN ONE PLACE. The editor's keyboard bridge already listens for `message`, and the
    // first version of this settled the overlay from there — which put "raise it" and "take it down"
    // in two hooks that know nothing about each other, and left the second silently dead whenever
    // the first was the only one mounted.
    this.onPainted = (event) => {
      if (!event.data || event.data.pb !== true || event.data.kind !== "painted") return;
      PB_FRAME_BUSY.settle(event.data.revision);
    };

    window.addEventListener("message", this.onPainted);
    PB_FRAME_BUSY.adopt();
  },
  destroyed() {
    window.removeEventListener("message", this.onPainted);
    PB_FRAME_BUSY.stop();
  },
};

// A SPINNER OVER AN IFRAME, REMOVED WHEN THE FRAME LOADS.
//
// The obvious CSS-only version does not work, and it is worth saying why: an iframe that has not
// loaded yet is NOT transparent — it paints its own white canvas — so a spinner placed BEHIND one is
// covered from the first frame and never seen. Measured, after shipping exactly that mistake.
//
// Nor can the spinner be swapped for the frame: replacing the element restarts the load, so it would
// never finish. So the spinner sits on top and this removes it, and the frame's `load` is the only
// signal available — the document inside is another origin (the canvas frames are sandboxed to an
// opaque one) and cannot report for itself.
//
// `data-frame` names the iframe. State lives on the hook rather than the DOM because LiveView strips
// `data-*` the server did not render on the next patch, `phx-update="ignore"` included.
const FrameLoader = {
  mounted() {
    this.watch();
  },
  updated() {
    this.watch();
  },
  watch() {
    const frame = document.getElementById(this.el.dataset.frame);
    if (!frame) return;

    // NEVER ASK `readyState`. A freshly created iframe reports "complete" for the `about:blank` it
    // starts on, so checking it hides the overlay on the very first tick and the reader sees the
    // blank frame this exists to explain. Measured, after shipping exactly that.
    //
    // The flag lives as a JS property on the FRAME rather than on this hook or a `data-*`: the hook
    // remounts whenever LiveView replaces the overlay, and `data-*` the server did not render is
    // stripped on the next patch. The frame element itself survives both.
    if (frame.__pbLoaded) return this.hide();

    if (!frame.__pbWatched) {
      frame.__pbWatched = true;
      const done = () => {
        frame.__pbLoaded = true;
        this.hide();
      };
      frame.addEventListener("load", done, { once: true });
      // A load that fails quietly would otherwise leave the spinner up for good; let whatever the
      // frame ends up showing speak for itself.
      frame.addEventListener("error", done, { once: true });
    }
  },
  hide() {
    this.el.style.display = "none";
  },
};

// THE SEO TAB'S VARIABLE CHIPS. A chip — `data-seo-var="{{page.title}}"` — puts its variable where
// the caret last was in one of the form's text fields marked `data-seo-vars`, and announces the
// change so the form's `phx-change` sends it. Nothing happens before such a field has been focused.
//
// The field is remembered by its `name`, so the one found on the click is the one on the page now,
// whatever a patch has done to the element in between.
const PbSeoFields = {
  mounted() {
    this.fieldName = null;

    // A field that takes no variables, such as a select's free value, forgets the last one that did.
    this.onFocus = (event) => {
      const target = event.target;

      if (seoTextField(target)) this.fieldName = target.name;
      else if (target.matches("input[type='text'], textarea")) this.fieldName = null;
    };

    this.onClick = (event) => {
      const chip = event.target.closest("[data-seo-var]");

      if (!chip || !this.el.contains(chip)) return;

      event.preventDefault();

      // The field last typed in, else the first that takes a variable — the title — at its end, so
      // a chip always lands somewhere the author can see.
      const fields = [...this.el.querySelectorAll("input, textarea")].filter(seoTextField);
      const remembered = fields.find((candidate) => candidate.name === this.fieldName);
      const field = remembered || fields[0];

      if (!field) return;

      if (!remembered) field.setSelectionRange(field.value.length, field.value.length);
      this.fieldName = field.name;
      insertAtCaret(field, chip.dataset.seoVar);
    };

    this.el.addEventListener("focusin", this.onFocus);
    this.el.addEventListener("click", this.onClick);

    // A value the editor chose for a field, such as the share image picked from Media: it is typed
    // in, so the field's own change writes it.
    this.handleEvent("pb-seo-set", ({ id, value }) => {
      const field = [...this.el.querySelectorAll("input, textarea")].find((el) => el.id === id);

      if (field) {
        field.value = value;
        field.dispatchEvent(new Event("input", { bubbles: true }));
      }
    });
  },
  destroyed() {
    this.el.removeEventListener("focusin", this.onFocus);
    this.el.removeEventListener("click", this.onClick);
  },
};

function seoTextField(el) {
  if (!el || !el.name || !el.hasAttribute("data-seo-vars")) return false;
  if (el.tagName === "TEXTAREA") return true;

  return el.tagName === "INPUT" && (el.type === "text" || el.type === "url");
}

// The text goes in place of the selection, the caret lands after it, and an `input` event tells
// LiveView the field changed.
function insertAtCaret(field, text) {
  const start = field.selectionStart ?? field.value.length;
  const end = field.selectionEnd ?? start;
  const caret = start + text.length;

  field.value = field.value.slice(0, start) + text + field.value.slice(end);
  field.focus();
  field.setSelectionRange(caret, caret);
  field.dispatchEvent(new Event("input", { bubbles: true }));
}

export default {
  FrameLoader,
  PbSeoFields,
  PbFrameBusy,
  UploadSubmitsItself,
  MentionBox,
  PbCopy,
  PbDragScroll,
  PbGrip,
  PbZoom,
  PbShortcuts,
  PbTheme,
  PbLeaveGuard,
  PbCanvas,
  PbPalettePrefs,
  PbContextMenu,
  PbPaletteItem,
  PbPaletteHover,
  PbLayers,
};
