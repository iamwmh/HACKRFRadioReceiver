const LANGS = [
  { id: "en", label: "EN" },
  { id: "fr-CA", label: "FR" },
  { id: "zh-Hans", label: "中文" }
];

function currentLang() {
  const query = new URLSearchParams(location.search).get("lang");
  const saved = localStorage.getItem("hackrf-site-lang");
  const pick = (query || saved || navigator.language || "en").toLowerCase();
  if (pick.startsWith("zh")) return "zh-Hans";
  if (pick.startsWith("fr")) return "fr-CA";
  return COPY[pick] ? pick : "en";
}

function pageHref(page, lang) {
  const here = document.body.dataset.page === "privacy";
  const href = page === "privacy" ? (here ? "./" : "privacy/") : (here ? "../" : "./");
  return `${href}?lang=${lang}`;
}

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

function renderChrome(lang, copy) {
  document.documentElement.lang = copy.htmlLang;
  const header = document.querySelector("[data-chrome]");
  header.replaceChildren();
  const brand = el("a", "brand");
  brand.href = pageHref("home", lang);
  const mark = document.createElement("img");
  mark.src = `${document.body.dataset.page === "privacy" ? "../" : ""}favicon.svg`;
  mark.alt = "";
  brand.append(mark, document.createTextNode("HACKRF"));
  const nav = el("nav", "nav");
  const help = el("a", null, copy.navHelp);
  help.href = pageHref("home", lang);
  const privacy = el("a", null, copy.navPrivacy);
  privacy.href = pageHref("privacy", lang);
  if (document.body.dataset.page === "home") help.setAttribute("aria-current", "page");
  if (document.body.dataset.page === "privacy") privacy.setAttribute("aria-current", "page");
  nav.append(help, privacy);
  const langs = el("div", "langs");
  for (const item of LANGS) {
    const button = el("button", null, item.label);
    button.type = "button";
    button.setAttribute("aria-pressed", item.id === lang ? "true" : "false");
    button.addEventListener("click", () => {
      localStorage.setItem("hackrf-site-lang", item.id);
      const url = new URL(location.href);
      url.searchParams.set("lang", item.id);
      history.replaceState(null, "", url);
      render();
    });
    langs.append(button);
  }
  header.append(brand, nav, langs);
  const footer = document.querySelector("[data-footer]");
  footer.replaceChildren();
  footer.append(el("span", null, copy.footer), el("a", null, copy.navPrivacy));
  footer.lastChild.href = pageHref("privacy", lang);
}

function renderHome(root, page) {
  const hero = el("header", "hero");
  hero.append(
    el("p", "kicker", page.kicker),
    el("h1", null, page.headline),
    el("p", "lead", page.lead)
  );
  const actions = el("div", "actions");
  const primary = el("a", "button primary", page.primary);
  primary.href = "#listen";
  const secondary = el("a", "button", page.secondary);
  secondary.href = pageHref("privacy", currentLang());
  actions.append(primary, secondary);
  hero.append(actions);
  const shot = el("figure", "shot");
  const image = document.createElement("img");
  image.src = "images/receiver.png";
  image.width = 1024;
  image.height = 640;
  image.alt = page.screenshotAlt;
  shot.append(image, el("figcaption", null, page.screenshotCaption));
  hero.append(shot);
  root.append(hero);

  page.sections.forEach((section, index) => {
    const block = el("section", "section");
    if (index === 2) block.id = "listen";
    block.append(el("h2", null, section.title));
    if (section.cards) {
      const columns = section.cards.length >= 4 ? "four" : section.cards.length === 3 ? "three" : "two";
      const grid = el("div", `grid ${columns}`);
      for (const card of section.cards) {
        const node = el("article", "card");
        if (card.freq) node.append(el("p", "freq", card.freq));
        node.append(el("h3", null, card.title), el("p", null, card.body));
        grid.append(node);
      }
      block.append(grid);
    }
    if (section.steps) {
      const list = document.createElement("ol");
      list.className = "steps card";
      for (const step of section.steps) list.append(el("li", null, step));
      block.append(list);
    }
    if (section.defs) {
      const list = document.createElement("dl");
      list.className = "ref card";
      for (const [term, detail] of section.defs) {
        const row = document.createElement("div");
        row.append(el("dt", null, term), el("dd", null, detail));
        list.append(row);
      }
      block.append(list);
    }
    if (section.paragraphs) {
      const card = el("div", "card");
      for (const paragraph of section.paragraphs) card.append(el("p", null, paragraph));
      block.append(card);
    }
    root.append(block);
  });
}

function renderPrivacy(root, page) {
  const hero = el("header", "hero");
  hero.append(
    el("p", "kicker", page.kicker),
    el("h1", null, page.headline),
    el("p", "updated", page.updated)
  );
  root.append(hero);
  const article = el("article", "legal");
  for (const section of page.sections) {
    article.append(el("h2", null, section.heading));
    for (const paragraph of section.paragraphs || []) article.append(el("p", null, paragraph));
    if (section.bullets) {
      const list = document.createElement("ul");
      for (const item of section.bullets) list.append(el("li", null, item));
      article.append(list);
    }
  }
  root.append(article);
}

function render() {
  const lang = currentLang();
  const copy = COPY[lang];
  const pageName = document.body.dataset.page;
  const page = copy[pageName];
  document.title = page.title;
  let meta = document.querySelector('meta[name="description"]');
  if (!meta) {
    meta = document.createElement("meta");
    meta.name = "description";
    document.head.append(meta);
  }
  meta.content = page.description;
  renderChrome(lang, copy);
  const root = document.querySelector("[data-root]");
  root.replaceChildren();
  if (pageName === "privacy") renderPrivacy(root, page);
  else renderHome(root, page);
}

render();
