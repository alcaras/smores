// S'mores Planner: the group (left) -> the camp plan (right): who drops what, the fire, blessings, sharing.
import { makeModel, LINES, LINE_NAME, ROLES, CLASSES, PLAN_MAX, defaultRole, exportPlan, importPlan, cleanName } from "./model.js";

const ICON = (name, size = "medium") => `https://wow.zamimg.com/images/wow/icons/${size}/${name}.jpg`;
const CLASS_ICON = (c) => ICON("classicon_" + c.toLowerCase());
const CLASS_NAME = (c) => c[0] + c.slice(1).toLowerCase();
const PROFESSION = { 129: "First Aid", 164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy", 182: "Herbalism",
  185: "Cooking", 186: "Mining", 197: "Tailoring", 202: "Engineering", 333: "Enchanting", 356: "Fishing", 393: "Skinning" };
const PRIMARY = [171, 164, 333, 202, 182, 165, 186, 393, 197];   // alphabetical by name
const SECONDARY_LIST = [185, 129, 356];
const SECONDARY = new Set(SECONDARY_LIST);   // anyone can learn these next to two primary ones
const FIRE_KIT = { 3: ["Basic Campfire Kit", 1], 5: ["Journeyman Campfire Kit", 140], 10: ["Expert Campfire Kit", 220] };
const STORE = "smores-last";     // the last group (was "smores-plan" until the level 30 leveling default)
const SAVED = "smores-saved";    // [{ name, roster, goal, fire, uptime }]
// the classes a primary profession usually goes with (armor it makes, what it gathers alongside)
const PROF_FIT = {
  165: ["ROGUE", "HUNTER", "DRUID", "SHAMAN"], 393: ["ROGUE", "HUNTER", "DRUID", "SHAMAN"],
  197: ["MAGE", "PRIEST", "WARLOCK"], 333: ["MAGE", "PRIEST", "WARLOCK"],
  164: ["WARRIOR", "PALADIN"], 186: ["WARRIOR", "PALADIN", "ROGUE", "HUNTER"],
  202: ["HUNTER", "WARRIOR", "ROGUE"], 182: ["DRUID", "PRIEST", "MAGE", "WARLOCK"], 171: [],
};

const $ = (id) => document.getElementById(id);
const el = (tag, attrs = {}, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") e.className = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else if (v !== undefined && v !== null && v !== false) e.setAttribute(k, v === true ? "" : v);
  }
  for (const k of kids.flat()) if (k !== null && k !== undefined && k !== false) e.append(k.nodeType ? k : String(k));
  return e;
};
const icon = (name, size = 20) => el("img", { src: ICON(name || "inv_misc_questionmark"), alt: "", width: size, height: size, loading: "lazy", class: "ico" });
const classIcon = (c, size = 20) => el("img", { src: CLASS_ICON(c), alt: "", width: size, height: size, class: "ico" });

// ------------------------------------------------------------------ tooltips: any element with data-tip (hover or focus)
const tipBox = el("div", { class: "tip", role: "tooltip", hidden: true });
document.body.append(tipBox);
function showTip(t) {
  tipBox.textContent = t.dataset.tip;
  tipBox.hidden = false;
  const r = t.getBoundingClientRect(), w = tipBox.offsetWidth, h = tipBox.offsetHeight;
  tipBox.style.left = Math.max(8, Math.min(r.left, innerWidth - w - 8)) + "px";
  tipBox.style.top = (r.bottom + 8 + h > innerHeight ? Math.max(8, r.top - h - 8) : r.bottom + 8) + "px";
}
const hideTip = () => { tipBox.hidden = true; };
document.addEventListener("mouseover", (e) => { const t = e.target.closest("[data-tip]"); t ? showTip(t) : hideTip(); });
document.addEventListener("focusin", (e) => { const t = e.target.closest("[data-tip]"); t ? showTip(t) : hideTip(); });
document.addEventListener("focusout", hideTip);
document.addEventListener("scroll", hideTip, { passive: true });
document.addEventListener("keydown", (e) => { if (e.key === "Escape") hideTip(); });

const D = await (await fetch("data.json", { cache: "no-cache" })).json();   // revalidate: new data after a patch
const M = makeModel(D);
$("build").textContent = "build " + D.build;

// ------------------------------------------------------------------ wording
function amountsText(a) {
  const parts = [];
  if (a.armor) parts.push(`+${a.armor} armor`);
  if (a.stat) parts.push(`+${a.stat} all stats`);
  if (a.res) parts.push(`+${a.res} resistances`);
  if (a.pct) parts.push(`+${a.pct}% all stats`);
  if (a.sta) parts.push(`+${a.sta} Stamina`);
  if (a.str) parts.push(`+${a.str} Strength`);
  if (a.ap) parts.push(`+${a.ap} melee attack power`);
  if (a.mp5) parts.push(`+${a.mp5} mana every 5 sec`);
  if (a.spi) parts.push(`+${a.spi} Spirit`);
  if (a.int) parts.push(`+${a.int} Intellect`);
  if (a.crit) parts.push(`+${a.crit}% crit`);
  return parts.join(", ") || "nothing yet at this level";
}
const KIND = { all: "", blessing: " blessing", totem: " totem", talent: " talent" };
const upgradesOf = (line) => Object.values(D.items).filter((it) => it.line === line && it.tier > 1).sort((a, b) => a.tier - b.tier);
const givesText = (line, level) => line === "tent" ? "rested XP to 5% of a level" : M.gives(line, level);

function featureTip(line, members) {
  const it = M.CAMP_ITEM[line];
  const prof = PROFESSION[it.skill];
  const out = [`${it.name}: ${prof} 20${SECONDARY.has(it.skill) ? " (a secondary profession)" : ""}.`];
  if (line === "tent") {
    out.push("Tops up rested XP to 5% of a level for everyone sitting nearby, once an hour each.",
      "Does nothing for someone already rested past that, or at level 60.");
  } else {
    out.push("Sit at the fire for 1 minute: the buff lasts 1 hour.");
    for (const L of [...new Set(members.map((m) => m.level))].sort((a, b) => a - b)) {
      out.push(`Level ${L}: ${amountsText(M.campAmounts(line, L))}`);
    }
    const c = D.class[line];
    const top = Math.max(...members.map((m) => m.level));
    out.push(`Same buff as ${c.name} (${CLASS_NAME(c.class)}${KIND[c.kind]}): they don't stack, the higher counts.`,
      `${c.name} at level ${top}: ${amountsText(M.classAmounts(line, top))}.`);
  }
  const ups = upgradesOf(line);
  if (ups.length) {
    out.push("Upgrades keep this buff and add:");
    for (const u of ups) out.push(`  ${u.name} (${prof} ${u.rank})${u.desc ? ": " + u.desc : ""}`);
  }
  return out.join("\n");
}

function cellTip(m, line, c, plan) {
  const name = `${m.name} (${m.role}), ${LINE_NAME[line]}`;
  if (c.kind === "missing") return `${name}: nobody in this plan brings it.`;
  const pct = Math.round((c.pct || 0) * 100);
  if (c.kind === "camp") return `${name}: ${M.CAMP_NAME[line]} from the camp, ${pct}% of the full buff.`;
  const blessed = (plan.bless[m.key] || []).includes(line);
  return `${name}: ${D.class[line].name}${blessed ? " (a paladin's blessing)" : ""}, ${pct}% of the full buff.`;
}

// ------------------------------------------------------------------ state (this browser, and the URL)
const DEFAULT = {
  roster: [
    { class: "WARRIOR", role: "tank", level: 30 }, { class: "ROGUE", role: "melee", level: 30 },
    { class: "MAGE", role: "caster", level: 30 }, { class: "PRIEST", role: "healer", level: 30 },
    { class: "HUNTER", role: "ranged", level: 30 },
  ],
  goal: "level", fire: 10, uptime: 70,
};
let state = structuredClone(DEFAULT);
try {
  const saved = JSON.parse(localStorage.getItem(STORE) || "null");
  if (saved && Array.isArray(saved.roster)) state = { ...state, ...saved };
  localStorage.removeItem("smores-plan");   // the old key: a level 60 group from before
} catch { /* storage blocked: start from the default */ }
const fromHash = importPlan(decodeURIComponent(location.hash.slice(1)));
if (fromHash && fromHash.roster.length) { state.roster = fromHash.roster; state.goal = fromHash.goal || "auto"; }

const code = () => exportPlan(state.roster, state.goal === "auto" ? null : state.goal);
function save() {
  try { localStorage.setItem(STORE, JSON.stringify(state)); } catch { /* fine without */ }
  history.replaceState(null, "", "#" + encodeURIComponent(code()).replace(/%2C/g, ",").replace(/%3A/g, ":"));
}

// ------------------------------------------------------------------ the group
let openPicker = null;   // the row whose professions picker is open (kept across re-renders)
const defaultName = (i) => M.planMembers(state.roster.map((e) => ({ ...e, name: undefined })))[i].name;

function profSummary(e) {
  return e.profs && e.profs.length ? e.profs.map((p) => PROFESSION[p]).join(", ") : "Professions: any";
}

function profPicker(e, i) {
  const summary = el("summary", { "data-tip": "Set the professions this person will have. Left on any, the plan says what to take." }, profSummary(e));
  const boxes = [];
  const refresh = () => {
    const chosen = new Set(e.profs || []);
    const primaries = PRIMARY.filter((p) => chosen.has(p)).length;
    for (const { p, input, label } of boxes) {
      const full = PRIMARY.includes(p) && primaries >= 2 && !chosen.has(p);
      input.checked = chosen.has(p);
      input.disabled = full;
      label.classList.toggle("off", full);
    }
    summary.textContent = profSummary(e);
  };
  const box = (p) => {
    const input = el("input", { type: "checkbox", onchange: (ev) => {
      const set = new Set(e.profs || []);
      if (ev.target.checked) set.add(p); else set.delete(p);
      e.profs = [...set].sort((a, b) => PROFESSION[a].localeCompare(PROFESSION[b]));
      if (!e.profs.length) delete e.profs;
      refresh();
      update();
    } });
    const label = el("label", { class: "prof-opt" }, input, " ", PROFESSION[p]);
    boxes.push({ p, input, label });
    return label;
  };
  const details = el("details", { class: "prof-pick", open: openPicker === i }, summary,
    el("div", { class: "prof-box" },
      el("div", { class: "prof-head" }, "Primary (up to 2)"), ...PRIMARY.map(box),
      el("div", { class: "prof-head" }, "Secondary (anyone can)"), ...SECONDARY_LIST.map(box),
      el("button", { type: "button", class: "small", onclick: () => { delete e.profs; refresh(); update(); } }, "Any")));
  details.addEventListener("toggle", () => {
    if (details.open) openPicker = i; else if (openPicker === i) openPicker = null;
  });
  refresh();
  return details;
}

function memberRow(e, i) {
  const img = el("img", { src: CLASS_ICON(e.class), alt: "", width: 28, height: 28, class: "cls" });
  const name = el("input", { class: "name", value: e.name || "", placeholder: defaultName(i), maxlength: 24,
    "aria-label": "Name", spellcheck: "false", "data-tip": "A name for the plan and the chat line (optional).",
    oninput: (ev) => { e.name = cleanName(ev.target.value) ? ev.target.value.trim().slice(0, 24) : undefined; update(); } });
  const roleSel = el("select", { "aria-label": "Role", "data-tip": "The plan weighs each buff by what the role uses.",
    onchange: (ev) => { e.role = ev.target.value; update(); } },
  ROLES.map((r) => el("option", { value: r, selected: r === e.role }, r)));
  const classSel = el("select", { "aria-label": "Class", onchange: (ev) => {
    e.class = ev.target.value;
    e.role = defaultRole(e.class);
    img.src = CLASS_ICON(e.class);
    roleSel.value = e.role;
    update();
    for (const [j, input] of [...document.querySelectorAll("#members input.name")].entries()) input.placeholder = defaultName(j);
  } }, CLASSES.map((c) => el("option", { value: c, selected: c === e.class }, CLASS_NAME(c))));
  const level = el("input", { type: "number", min: 1, max: 60, step: 1, value: e.level, "aria-label": "Level",
    onchange: (ev) => { e.level = Math.max(1, Math.min(60, Math.round(+ev.target.value || 60))); ev.target.value = e.level; update(); } });
  return el("li", { class: "member" }, img, name, classSel, roleSel, level,
    el("button", { type: "button", class: "x", "aria-label": "Remove", "data-tip": "Remove from the group",
      onclick: () => { state.roster.splice(i, 1); openPicker = null; renderGroup(); update(); } }, "×"),
    profPicker(e, i));
}

function renderGroup() {
  $("members").replaceChildren(...state.roster.map(memberRow));
  $("count").textContent = `${state.roster.length} / ${PLAN_MAX}`;
}

function addMember(c) {
  if (state.roster.length >= PLAN_MAX) return;
  const level = state.roster[0] ? state.roster[0].level : 30;
  state.roster.push({ class: c, role: defaultRole(c), level });
  renderGroup();
  update();
  const names = document.querySelectorAll("#members input.name");
  names[names.length - 1]?.focus();
}
$("add-classes").replaceChildren(...CLASSES.map((c) => el("button", { type: "button", class: "pick",
  "data-tip": `Add a ${CLASS_NAME(c)} (up to ${PLAN_MAX})`, "aria-label": "Add a " + CLASS_NAME(c), onclick: () => addMember(c) },
el("img", { src: CLASS_ICON(c), alt: "", width: 28, height: 28 }))));

// ------------------------------------------------------------------ the plan
function resolvedGoal(members) {
  if (state.goal !== "auto") return state.goal;
  const top = Math.max(0, ...members.map((m) => m.level));
  return top > 0 && top < 60 ? "level" : "progress";
}

// members left on "any" profession: hand their features out by profession fit
function assignment(members, theory) {
  const lineOf = {};
  for (const [line, i] of Object.entries(theory.assign || {})) lineOf[i] = line;
  const flexIdx = members.map((m, i) => i).filter((i) => !members[i].can && lineOf[i]);
  const pool = flexIdx.map((i) => lineOf[i]);
  pool.sort((a, b) => SECONDARY.has(M.CAMP_ITEM[a].skill) - SECONDARY.has(M.CAMP_ITEM[b].skill));
  const free = new Set(flexIdx);
  for (const line of pool) {
    const fit = PROF_FIT[M.CAMP_ITEM[line].skill] || [];
    const pick = [...free].find((i) => fit.includes(members[i].class)) ?? [...free][0];
    lineOf[pick] = line;
    free.delete(pick);
  }
  return members.map((m, i) => ({ m, line: lineOf[i] || null }));
}

let last = null;   // { members, plan, rows, goal } for the share buttons

function personRow({ m, line }, plan, level) {
  const who = el("div", { class: "who" }, classIcon(m.class, 24),
    el("span", { class: "pname c-" + m.class.toLowerCase(), "data-tip": `${m.name}: ${CLASS_NAME(m.class)}, ${m.role}, level ${m.level}` +
      (m.profs ? `, ${m.profs.map((p) => PROFESSION[p]).join(", ")}` : "") }, m.name));
  const blessings = (plan.bless[m.key] || []).map((b) => el("span", { class: "chip-b", "data-tip": `${D.class[b].name} from a paladin` },
    icon(D.class[b].icon, 14), " ", D.class[b].name));
  if (!line) {
    const theirs = (m.profs || []).map((p) => PROFESSION[p]).join(", ");
    let why = "nothing to drop: free to take any professions";
    if (m.can && !m.can.length) why = `${theirs}: places no buff feature`;
    else if (m.can) why = `${theirs}: nothing this camp still needs`;
    return el("li", { class: "person none" }, who, el("div", { class: "what muted" }, why), el("div", { class: "how" }, ...blessings));
  }
  const it = M.CAMP_ITEM[line];
  const prof = PROFESSION[it.skill];
  const how = m.can ? `their ${prof}` : `take ${prof}${SECONDARY.has(it.skill) ? " (secondary)" : ""}`;
  return el("li", { class: "person", tabindex: 0, "data-tip": featureTip(line, plan.members) }, who,
    el("div", { class: "what" }, icon(it.icon, 24), el("span", { class: "fname" }, it.name),
      el("span", { class: "gives" }, givesText(line, level))),
    el("div", { class: "how" }, el("span", { class: "muted" }, how), ...blessings));
}

function update() {
  save();
  const members = M.planMembers(state.roster);
  for (const b of document.querySelectorAll("#goal button")) b.setAttribute("aria-pressed", String(b.dataset.v === state.goal));
  for (const b of document.querySelectorAll("#fire button")) b.setAttribute("aria-pressed", String(+b.dataset.v === state.fire));
  $("uptime").value = state.uptime;
  $("uptime-out").textContent = state.uptime + "%";
  $("count").textContent = `${state.roster.length} / ${PLAN_MAX}`;
  if (!members.length) {
    $("people").replaceChildren(el("li", { class: "empty" }, "Add people on the left to see their camp."));
    for (const id of ["extras", "grid", "ref"]) $(id).replaceChildren();
    $("pct").textContent = "0%";
    last = null;
    return;
  }
  const goal = resolvedGoal(members);
  const opts = { goal, uptime: state.uptime / 100, maxLevel: 60, seen: {}, cap: state.fire };
  const theory = M.theory(members, opts);
  const plan = M.planWithCamp(members, theory.lines, opts);
  plan.members = members;
  const level = Math.max(...members.map((m) => m.level));
  const rows = assignment(members, theory);
  last = { members, plan, rows, goal };
  $("pct").textContent = Math.round(plan.pct * 100) + "%";
  $("people").replaceChildren(...rows.map((r) => personRow(r, plan, level)));
  renderExtras(members, plan, theory, goal);
  renderGrid(members, plan);
  renderRef(level);
}

function renderExtras(members, plan, theory, goal) {
  const out = [];
  const [kit, rank] = FIRE_KIT[state.fire];
  const cooks = members.filter((m) => (m.profs || []).includes(185)).map((m) => m.name);
  out.push(el("p", { tabindex: 0, "data-tip": "Basic Campfire Kit (Cooking 1) holds 3 features, Journeyman (Cooking 140) 5, Expert (Cooking 220) 10. The fire and every feature last 15 minutes; sit 1 minute for 1 hour of buffs." },
    el("strong", {}, "Fire "), icon("inv_camelot_camping_welcomingcampfire", 16), ` ${kit}: Cooking ${rank}, `,
    cooks.length ? cooks.join(", ") : "anyone (Cooking is secondary)", el("span", { class: "muted" }, ` · ${theory.lines.length} of ${state.fire} places used`)));
  const by = {};
  for (const m of members) for (const b of plan.bless[m.key] || []) (by[b] ||= []).push(m.name);
  if (Object.keys(by).length) {
    out.push(el("p", { tabindex: 0, "data-tip": "Each paladin gives every class one blessing. Each person gets the blessing whose camp copy is weakest or missing; the camp covers the rest." },
      el("strong", {}, "Blessings "), ...Object.entries(by).flatMap(([b, who], i) => [
        i ? "; " : "", icon(D.class[b].icon, 16), " ", D.class[b].name, " → ", who.join(", ")])));
  }
  if (plan.totem) {
    out.push(el("p", { tabindex: 0, "data-tip": "A shaman has one earth totem at a time. With a Sharpening Wheel down, the earth slot is free for Stoneskin or Tremor at little cost. Set the uptime under Options." },
      el("strong", {}, "Totem "), icon(D.class.str.icon, 16),
      ` Strength of Earth ~${Math.round(plan.totem.soe)} Str at ${state.uptime}% uptime, a Sharpening Wheel ${plan.totem.wheel}.`));
  }
  if (plan.need.length) {
    out.push(el("p", { tabindex: 0, "data-tip": "These would still add something, but the fire is full, everyone already places one, or nobody's professions place them." },
      el("strong", {}, "Also useful "), ...plan.need.slice(0, 3).flatMap((n, i) => [
        i ? ", " : "", icon(M.CAMP_ITEM[n.line].icon, 16), " ", M.CAMP_NAME[n.line]])));
  }
  out.push(el("p", { class: "muted" }, goal === "level"
    ? "Planning for leveling: rested XP from a Camp Tent counts; mana and spirit weigh more."
    : "Planning for progression: power only; the tent counts for nothing."));
  $("extras").replaceChildren(...out);
}

function renderGrid(members, plan) {
  const head = el("tr", {}, el("th", { scope: "col" }, ""), ...members.map((m) =>
    el("th", { scope: "col", tabindex: 0, "data-tip": `${m.name}: ${m.role}, level ${m.level}` },
      el("img", { src: CLASS_ICON(m.class), alt: "", width: 18, height: 18 }), el("span", { class: "gname" }, m.name))));
  const rows = LINES.map((line) => el("tr", {},
    el("th", { scope: "row", tabindex: 0, "data-tip": line === "tent"
      ? "Rested XP: only the Camp Tent (Leatherworking) gives it."
      : `${LINE_NAME[line]}: the class buff ${D.class[line].name} (${CLASS_NAME(D.class[line].class)}) or the camp's ${M.CAMP_NAME[line]} (${PROFESSION[M.CAMP_ITEM[line].skill]}).` },
    icon(M.CAMP_ITEM[line].icon, 16), " ", LINE_NAME[line]),
    ...members.map((m) => {
      const c = plan.cells[m.key][line];
      if (!c || c.kind === "none") return el("td", {});
      return el("td", { class: "k-" + c.kind, tabindex: 0, "data-tip": cellTip(m, line, c, plan) }, String(Math.round((c.pct || 0) * 100)));
    })));
  $("grid").replaceChildren(el("thead", {}, head), el("tbody", {}, rows));
}

// every camp feature: what it gives at the group's level, the class buff it copies, its upgrades
function renderRef(level) {
  $("ref-hint").textContent = `At level ${level}, the group's highest. Each person places one feature an hour; the higher of a camp buff and its class buff counts.`;
  const head = el("tr", {}, ...["Feature", "Profession", "Gives", "Class buff", "Upgrades"].map((t) => el("th", { scope: "col" }, t)));
  const rows = LINES.map((line) => {
    const it = M.CAMP_ITEM[line];
    const c = D.class[line];
    return el("tr", {},
      el("th", { scope: "row", tabindex: 0, "data-tip": featureTip(line, [{ level }]) }, icon(it.icon, 18), " ", it.name),
      el("td", {}, `${PROFESSION[it.skill]} 20`),
      el("td", {}, line === "tent" ? "rested XP to 5% of a level, once an hour" : amountsText(M.campAmounts(line, level))),
      el("td", {}, line === "tent" ? "none" : [icon(c.icon, 16), " ", `${c.name}: ${amountsText(M.classAmounts(line, level))}`]),
      el("td", {}, upgradesOf(line).map((u) => `${u.name} (${u.rank})`).join(", ")));
  });
  $("ref").replaceChildren(el("thead", {}, head), el("tbody", {}, rows));
}

// ------------------------------------------------------------------ sharing
function chatLine() {
  if (!last) return "";
  const drops = last.rows.filter((r) => r.line).map((r) => `${r.m.name} ${M.CAMP_ITEM[r.line].name}`);
  let s = "S'mores: " + (drops.length ? drops.join(", ") : "nothing to drop");
  const by = {};
  for (const m of last.members) for (const b of last.plan.bless[m.key] || []) (by[b] ||= []).push(m.name);
  const bless = Object.entries(by).map(([b, who]) => `${D.class[b].name} > ${who.join(", ")}`);
  if (bless.length) s += ". Blessings: " + bless.join("; ");
  s += `. Fire: ${FIRE_KIT[state.fire][0].replace(" Campfire Kit", "")} (Cooking ${FIRE_KIT[state.fire][1]})`;
  return s;
}
async function copy(button, text) {
  const was = button.textContent;
  try { await navigator.clipboard.writeText(text); button.textContent = "Copied"; }
  catch { window.prompt("Copy this:", text); }
  setTimeout(() => { button.textContent = was; }, 1400);
}
$("share-link").addEventListener("click", (ev) => copy(ev.currentTarget, location.href));
$("share-code").addEventListener("click", (ev) => copy(ev.currentTarget, code()));
$("share-chat").addEventListener("click", (ev) => copy(ev.currentTarget, chatLine()));
$("import-form").addEventListener("submit", (ev) => {
  ev.preventDefault();
  const raw = $("import-code").value.trim();
  const got = importPlan(raw.includes("#") ? decodeURIComponent(raw.slice(raw.indexOf("#") + 1)) : raw);
  const err = $("import-error");
  if (!got || !got.roster.length) {
    err.textContent = "That isn't an S'mores plan code or link. Codes start with SM1:";
    err.hidden = false;
    return;
  }
  err.hidden = true;
  state.roster = got.roster;
  state.goal = got.goal || "auto";
  $("import-code").value = "";
  ev.target.closest("details").open = false;
  openPicker = null;
  renderGroup();
  update();
});
$("import-code").addEventListener("input", () => { $("import-error").hidden = true; });

// ------------------------------------------------------------------ groups (this browser)
function readSaved() {
  try { return JSON.parse(localStorage.getItem(SAVED) || "[]").filter((s) => s && s.name && Array.isArray(s.roster)); }
  catch { return []; }
}
function writeSaved(list) {
  try { localStorage.setItem(SAVED, JSON.stringify(list)); return true; } catch { return false; }
}
function loadGroup(g) {
  state = { ...state, roster: structuredClone(g.roster), goal: g.goal || state.goal, fire: g.fire || state.fire, uptime: g.uptime ?? state.uptime };
  openPicker = null;
  $("groups-menu").open = false;
  renderGroup();
  update();
}
function renderSaved() {
  const list = readSaved();
  $("saved").replaceChildren(...(list.length ? list.map((s, i) => el("li", { class: "saved-item" },
    el("button", { type: "button", class: "saved-load", "data-tip": s.roster.map((e) => (e.name || CLASS_NAME(e.class)) + " " + e.level).join(", "),
      onclick: () => loadGroup(s) }, s.name, el("span", { class: "muted" }, ` · ${s.roster.length}`)),
    el("button", { type: "button", class: "x", "aria-label": "Delete " + s.name, "data-tip": "Delete this saved group",
      onclick: () => { const l = readSaved(); l.splice(i, 1); writeSaved(l); renderSaved(); } }, "×")))
    : [el("li", { class: "muted" }, "Nothing saved yet.")]));
}
$("save-form").addEventListener("submit", (ev) => {
  ev.preventDefault();
  const name = $("save-name").value.trim();
  if (!name || !state.roster.length) { $("save-name").focus(); return; }
  const list = readSaved().filter((s) => s.name !== name);
  list.unshift({ name, roster: structuredClone(state.roster), goal: state.goal, fire: state.fire, uptime: state.uptime });
  writeSaved(list.slice(0, 30));
  $("save-name").value = "";
  renderSaved();
});
$("new-starter").addEventListener("click", () => loadGroup({ roster: DEFAULT.roster, goal: "level" }));
$("new-empty").addEventListener("click", () => loadGroup({ roster: [] }));

// ------------------------------------------------------------------ controls
for (const b of document.querySelectorAll("#goal button")) b.addEventListener("click", () => { state.goal = b.dataset.v; update(); });
for (const b of document.querySelectorAll("#fire button")) b.addEventListener("click", () => { state.fire = +b.dataset.v; update(); });
$("uptime").addEventListener("input", (ev) => { state.uptime = +ev.target.value; update(); });
$("all-level").addEventListener("change", (ev) => {
  const v = Math.max(1, Math.min(60, Math.round(+ev.target.value || 30)));
  ev.target.value = v;
  for (const e of state.roster) e.level = v;
  renderGroup();
  update();
});

renderGroup();
renderSaved();
update();
