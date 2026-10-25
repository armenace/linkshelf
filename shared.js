/* =====================================================================
   Linkshelf: shared code for the editor (index.html) and public pages (page.html)
   ===================================================================== */

/* ---------- 1. YOUR SUPABASE PROJECT (edit these two lines) ----------
   Supabase dashboard -> your project -> "Connect" button (or Settings -> API Keys).
   Use the PUBLISHABLE key (starts with sb_publishable_) or the legacy "anon" key.
   Both are safe in public code: the database rules in schema.sql protect the data.
   NEVER paste a "secret" or "service_role" key here. */
const SUPABASE_URL = "https://xfqknzlbrodjgdfsttbc.supabase.co";
const SUPABASE_KEY = "sb_publishable_6DnsKOlJI24iYEBpQ199DA_HLy7RvPm";

/* ---------- 2. Connection ---------- */
const isConfigured = !SUPABASE_URL.includes("YOUR-PROJECT") && !SUPABASE_KEY.startsWith("PASTE");
const db = isConfigured ? window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY) : null;

/* ---------- 3. Themes (must match the list in schema.sql) ---------- */
const THEMES = {
  cobalt: { label: "Cobalt", swatch: ["#2B3BFF", "#FF7AC6"] },
  paper:  { label: "Paper",  swatch: ["#FFFFFF", "#16163A"] },
  night:  { label: "Night",  swatch: ["#16163A", "#FF7AC6"] },
  lemon:  { label: "Lemon",  swatch: ["#FFE14D", "#16163A"] },
  mint:   { label: "Mint",   swatch: ["#C9F2E1", "#0F3D2E"] }
};

/* ---------- 4. Small helpers ---------- */

// Only allow real web links. Anything else (javascript:, data:, etc.) is refused.
function safeUrl(raw) {
  let v = String(raw || "").trim();
  if (!v) return null;
  if (!/^[a-z][a-z0-9+.-]*:/i.test(v)) v = "https://" + v;      // "github.com/x" -> "https://github.com/x"
  try {
    const u = new URL(v);
    if (u.protocol !== "http:" && u.protocol !== "https:") return null;
    if (!u.hostname.includes(".")) return null;
    return u.href;
  } catch { return null; }
}

function initials(name, username) {
  const src = (name || username || "?").trim();
  const parts = src.split(/\s+/).filter(Boolean);
  return ((parts[0]?.[0] || "?") + (parts[1]?.[0] || "")).toUpperCase();
}

function publicUrl(username) {
  return new URL("page.html?u=" + encodeURIComponent(username), location.href).href;
}

// Build an element safely: text is always set with textContent, never innerHTML.
function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (v == null || v === false) continue;
    if (k === "class") node.className = v;
    else if (k === "text") node.textContent = v;
    else if (k.startsWith("on")) node.addEventListener(k.slice(2), v);
    else node.setAttribute(k, v === true ? "" : v);
  }
  for (const c of children.flat()) if (c != null) node.append(c);
  return node;
}

/* ---------- 5. The page renderer ----------
   Used by the live preview in the editor AND by the real public page,
   so what people see in the preview is exactly what visitors get. */
function renderShelf(target, profile, links, { preview = false } = {}) {
  const theme = THEMES[profile.theme] ? profile.theme : "cobalt";
  target.className = "shelf theme-" + theme + (preview ? " is-preview" : "");
  target.replaceChildren();

  const list = el("ul", { class: "shelf-links" });
  for (const link of links) {
    const href = safeUrl(link.url);
    if (!href) continue;
    const a = el("a", {
      class: "shelf-link",
      href,
      target: "_blank",
      rel: "noopener noreferrer",
      tabindex: preview ? "-1" : null,
      onclick: preview
        ? e => e.preventDefault()
        : () => { if (db && link.id) db.rpc("increment_click", { link_id: link.id }).then(() => {}, () => {}); }
    }, el("span", { text: link.title }));
    list.append(el("li", {}, a));
  }

  target.append(
    el("div", { class: "shelf-inner" },
      el("div", { class: "shelf-avatar", "aria-hidden": "true", text: initials(profile.display_name, profile.username) }),
      el(preview ? "p" : "h1", { class: "shelf-name", text: profile.display_name || "@" + profile.username }),
      profile.display_name ? el("p", { class: "shelf-handle", text: "@" + profile.username }) : null,
      profile.bio ? el("p", { class: "shelf-bio", text: profile.bio }) : null,
      links.length
        ? list
        : el("p", { class: "shelf-empty", text: preview ? "Your links will show up here." : "No links yet." }),
      el("p", { class: "shelf-foot" },
        el("a", { href: new URL("index.html", location.href).href, tabindex: preview ? "-1" : null, text: "Make your own on Linkshelf" }))
    )
  );
}
