// S'mores Planner: the addon's plan mode in a page. Roster -> theory camp (model.js) -> camp list, blessings, grid.
import { makeModel, LINES, LINE_NAME, ROLES, CLASSES, PLAN_MAX, defaultRole, exportPlan, importPlan } from "./model.js";

const ICON = (name, size = "medium") => `https://wow.zamimg.com/images/wow/icons/${size}/${name}.jpg`;
const CLASS_ICON = (c) => ICON("classicon_" + c.toLowerCase());
const CLASS_NAME = (c) => c[0] + c.slice(1).toLowerCase();
const PROFESSION = { 129: "First Aid", 164: "Blacksmithing", 165: "Leatherworking", 171: "Alchemy", 182: "Herbalism",
  185: "Cooking", 186: "Mining", 197: "Tailoring", 202: "Engineering", 333: "Enchanting", 356: "Fishing", 393: "Skinning" };
const STORE = "smores-last";   // the last group (was "smores-plan" until the level 30 leveling default)
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
const icon = (name, alt = "", size = 20) => el("img", { src: ICON(name), alt, width: size, height: size, loading: "lazy", class: "ico" });

// ------------------------------------------------------------------ tooltips: any element with data-tip (hover or focus)
const tipBox = el("div", { class: "tip", role: "tooltip", hidden: true });
document.body.append(tipBox);
function showTip(t) {
  tipBox.textContent = t.dataset.tip;
  tipBox.hidden = false;
  const r = t.getBoundingClientRect(), w = tipBox.offsetWidth, h = tipBox.offsetHeight;
  const x = Math.max(8, Math.min(r.left, innerWidth - w - 8));
  const y = r.bottom + 8 + h > innerHeight ? Math.max(8, r.top - h - 8) : r.bottom + 8;
  tipBox.style.left = x + "px";
  tipBox.style.top = y + "px";
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

// "+163 armor, +7 stats, +6 resistances" for a buff line's amounts
function amountsText(line, a) {
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
const levelsOf = (members) => [...new Set(members.map((m) => m.level))].sort((a, b) => a - b);
const upgradesOf = (line) => Object.values(D.items).filter((it) => it.line === line && it.tier > 1)
  .sort((a, b) => a.tier - b.tier);

function classBuffTip(line, level) {
  const c = D.class[line];
  return `${c.name}: ${CLASS_NAME(c.class)}${KIND[c.kind]}.\nAt level ${level}: ${amountsText(line, M.classAmounts(line, level))}.` +
    (c.kind === "totem" ? "\nTotems last 5 min and reach only the shaman's party." : "") +
    (c.kind === "talent" ? "\nOnly a caster who took the talent has it." : "");
}

function featureTip(line, members) {
  const it = M.CAMP_ITEM[line];
  const prof = PROFESSION[it.skill];
  const out = [`${it.name}: ${prof} 20${SECONDARY.has(it.skill) ? " (a secondary profession)" : ""}.`];
  if (line === "tent") {
    out.push("Tops up rested XP to 5% of a level for everyone sitting nearby, once an hour each.",
      "Does nothing for someone already rested past that, or at level 60.");
  } else {
    out.push("Sit at the fire for 1 minute: the buff lasts 1 hour.");
    for (const L of levelsOf(members)) out.push(`Level ${L}: ${amountsText(line, M.campAmounts(line, L))}`);
    const c = D.class[line];
    const top = Math.max(...members.map((m) => m.level));
    out.push(`Same buff as ${c.name} (${CLASS_NAME(c.class)}${KIND[c.kind]}): they don't stack, the higher counts.`,
      `${c.name} at level ${top}: ${amountsText(line, M.classAmounts(line, top))}.`);
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
  return `${name}: ${D.class[line].name}${blessed ? " (the paladin's blessing for this member)" : ""}, ${pct}% of the full buff.`;
}

// ------------------------------------------------------------------ state (saved in this browser, shared by the URL)
// most players are leveling: a level 30 group, planned for XP
const DEFAULT = {
  roster: [
    { class: "WARRIOR", role: "tank", level: 30 }, { class: "ROGUE", role: "melee", level: 30 },
    { class: "MAGE", role: "caster", level: 30 }, { class: "PRIEST", role: "healer", level: 30 },
    { class: "HUNTER", role: "ranged", level: 30 },
  ],
  goal: "level", fire: 10, uptime: 70,
};
const SAVED = "smores-saved";   // [{ name, roster, goal, fire, uptime }]
const SECONDARY = new Set([129, 185, 356]);   // First Aid, Cooking, Fishing: anyone can learn them
const FIRE_COOKING = { 3: ["Basic Campfire Kit", 1], 5: ["Journeyman Campfire Kit", 140], 10: ["Expert Campfire Kit", 220] };
const PRIMARY = [171, 164, 333, 202, 182, 165, 186, 393, 197];   // alphabetical by name
const SECONDARY_LIST = [185, 129, 356];
let openPicker = null;   // the roster row whose professions picker is open (kept across re-renders)
let state = structuredClone(DEFAULT);
try {
  const saved = JSON.parse(localStorage.getItem(STORE) || "null");
  if (saved && Array.isArray(saved.roster)) state = { ...state, ...saved };
} catch { /* storage blocked: start from the default */ }
try { localStorage.removeItem("smores-plan"); } catch { /* the old key: a level 60 group from before */ }
const fromHash = importPlan(decodeURIComponent(location.hash.slice(1)));
if (fromHash && fromHash.roster.length) { state.roster = fromHash.roster; state.goal = fromHash.goal || "auto"; }

function save() {
  try { localStorage.setItem(STORE, JSON.stringify(state)); } catch { /* fine without */ }
  const code = exportPlan(state.roster, state.goal === "auto" ? null : state.goal);
  history.replaceState(null, "", "#" + code);
  return code;
}

// ------------------------------------------------------------------ roster
// planned professions: up to two primary, any secondary; none = "any" (the plan says what to take)
function profPicker(e, i, name) {
  const chosen = new Set(e.profs || []);
  const primaries = PRIMARY.filter((p) => chosen.has(p)).length;
  const box = (p) => {
    const full = PRIMARY.includes(p) && primaries >= 2 && !chosen.has(p);
    return el("label", { class: "prof-opt" + (full ? " off" : "") },
      el("input", { type: "checkbox", checked: chosen.has(p), disabled: full, onchange: (ev) => {
        const set = new Set(e.profs || []);
        if (ev.target.checked) set.add(p); else set.delete(p);
        e.profs = [...set].sort((a, b) => a - b);
        if (!e.profs.length) delete e.profs;
        render();
      } }), " ", PROFESSION[p]);
  };
  const label = chosen.size ? [...chosen].map((p) => PROFESSION[p]).join(", ") : "Professions: any";
  const details = el("details", { class: "prof-pick", open: openPicker === i },
    el("summary", { "data-tip": chosen.size
      ? `${name} can only drop what these professions place.`
      : `Set the professions ${name} will have. Left on "any", the plan says what to take.` }, label),
    el("div", { class: "prof-box" },
      el("div", { class: "prof-head" }, "Primary (up to 2)"), ...PRIMARY.map(box),
      el("div", { class: "prof-head" }, "Secondary (anyone)"), ...SECONDARY_LIST.map(box),
      el("button", { type: "button", class: "prof-any", onclick: () => { delete e.profs; render(); } }, "Any")));
  details.addEventListener("toggle", () => {
    if (details.open) openPicker = i; else if (openPicker === i) openPicker = null;
  });
  return details;
}

function memberRow(e, i, names) {
  const classSel = el("select", { "aria-label": "Class", onchange: (ev) => {
    e.class = ev.target.value; e.role = defaultRole(e.class); render();
  } }, CLASSES.map((c) => el("option", { value: c, selected: c === e.class }, CLASS_NAME(c))));
  const roleSel = el("select", { "aria-label": "Role", onchange: (ev) => { e.role = ev.target.value; render(); } },
    ROLES.map((r) => el("option", { value: r, selected: r === e.role }, r)));
  const level = el("input", { type: "number", min: 1, max: 60, step: 1, value: e.level, "aria-label": "Level",
    onchange: (ev) => { e.level = Math.max(1, Math.min(60, Math.round(+ev.target.value || 60))); render(); } });
  return el("li", { class: "member" },
    el("img", { src: CLASS_ICON(e.class), alt: names[i], "data-tip": `${names[i]}: ${e.role}, level ${e.level}` + (e.profs ? `, ${e.profs.map((p) => PROFESSION[p]).join(", ")}` : "") + ". Change the class, role, level and professions here.", width: 28, height: 28, class: "cls", tabindex: 0 }),
    classSel, roleSel, level,
    el("button", { type: "button", class: "x", "aria-label": "Remove " + names[i], onclick: () => { state.roster.splice(i, 1); openPicker = null; render(); } }, "×"),
    profPicker(e, i, names[i]));
}

function renderAddButtons() {
  const box = $("add-classes");
  box.replaceChildren(...CLASSES.map((c) => el("button", {
    type: "button", class: "pick", "data-tip": `Add a ${CLASS_NAME(c)} (up to ${PLAN_MAX})`, "aria-label": "Add a " + CLASS_NAME(c),
    onclick: () => {
      if (state.roster.length >= PLAN_MAX) return;
      const level = state.roster[0] ? state.roster[0].level : 60;
      state.roster.push({ class: c, role: defaultRole(c), level });
      render();
    },
  }, el("img", { src: CLASS_ICON(c), alt: "", width: 28, height: 28 }))));
}

// ------------------------------------------------------------------ results
function resolvedGoal(members) {
  if (state.goal !== "auto") return state.goal;
  const top = Math.max(0, ...members.map((m) => m.level));
  return top > 0 && top < 60 ? "level" : "progress";
}

function campCard(line, level, members) {
  const it = M.CAMP_ITEM[line];
  const cls = D.class[line];
  const prof = PROFESSION[it.skill] || "";
  return el("li", { class: "feature", tabindex: 0, "data-tip": featureTip(line, members) },
    icon(it.icon || "inv_misc_questionmark", "", 36),
    el("div", {},
      el("div", { class: "fname" }, it.name, " ", el("span", { class: "gives" },
        line === "tent" ? "rested XP to 5% of a level, once an hour" : M.gives(line, level))),
      el("div", { class: "fmeta" }, line === "tent" ? `${prof} 20 · for leveling` : `${prof} 20 · same buff as `,
        line === "tent" ? null : el("span", { class: "cbuff", "data-tip": classBuffTip(line, level) }, icon(cls.icon, "", 14), " ", cls.name))));
}

// the classes a primary profession usually goes with (armor it makes, what it gathers alongside)
const PROF_FIT = {
  165: ["ROGUE", "HUNTER", "DRUID", "SHAMAN"], 393: ["ROGUE", "HUNTER", "DRUID", "SHAMAN"],
  197: ["MAGE", "PRIEST", "WARLOCK"], 333: ["MAGE", "PRIEST", "WARLOCK"],
  164: ["WARRIOR", "PALADIN"], 186: ["WARRIOR", "PALADIN", "ROGUE", "HUNTER"],
  202: ["HUNTER", "WARRIOR", "ROGUE"], 182: ["DRUID", "PRIEST", "MAGE", "WARLOCK"], 171: [],
};

// hands each camp feature to one member: primary professions to a class that usually takes them, then the
// secondary ones (First Aid, Fishing) to whoever is left
function whoBrings(members, lines) {
  const order = [...lines].sort((a, b) => SECONDARY.has(M.CAMP_ITEM[a].skill) - SECONDARY.has(M.CAMP_ITEM[b].skill));
  const out = members.map((m) => ({ m, line: null }));
  for (const line of order) {
    const fit = PROF_FIT[M.CAMP_ITEM[line].skill] || [];
    const free = out.filter((o) => !o.line);
    const pick = free.find((o) => fit.includes(o.m.class)) || free[0];
    if (pick) pick.line = line;
  }
  return out;
}

// the plan's assignment (line -> member); members left on "any" share their lines out by profession fit
function assignment(members, theory) {
  const lineOf = {};
  for (const [line, i] of Object.entries(theory.assign || {})) lineOf[i] = line;
  const flexible = members.filter((m, i) => !m.can && lineOf[i]);
  const reshuffled = whoBrings(flexible, flexible.map((m) => lineOf[members.indexOf(m)]));
  for (const { m, line } of reshuffled) lineOf[members.indexOf(m)] = line;
  return members.map((m, i) => ({ m, line: lineOf[i] || null }));
}

function renderProfs(members, theory) {
  const rows = assignment(members, theory).map(({ m, line }) => {
    const who = [el("img", { src: CLASS_ICON(m.class), alt: "", width: 20, height: 20, class: "ico" }), " ",
      el("span", { class: "c-" + m.class.toLowerCase() }, m.name)];
    const theirs = (m.profs || []).map((p) => PROFESSION[p]).join(", ");
    if (!line) {
      let why = "free to pick anything", tipText = "This plan has no feature left for them: their professions are free.";
      if (m.can && !m.can.length) {
        why = `${theirs}: nothing that gives a buff`;
        tipText = "None of these professions places a buff feature (Engineering places only the Reagent and Repair Bots).";
      } else if (m.can) {
        why = `${theirs}: nothing this camp needs`;
        tipText = "What their professions place is already covered by a class buff, or the fire is full.";
      }
      return el("li", { tabindex: 0, "data-tip": tipText }, ...who, el("span", { class: "muted" }, " " + why));
    }
    const it = M.CAMP_ITEM[line];
    const prof = PROFESSION[it.skill];
    if (m.can) {
      return el("li", { tabindex: 0, "data-tip": `${m.name} has ${theirs}: ${prof} places the ${it.name}.` },
        ...who, " drops ", icon(it.icon, "", 18), " ", it.name, " ", el("span", { class: "muted" }, `(their ${prof})`));
    }
    const ups = upgradesOf(line).map((u) => `${u.name} at ${prof} ${u.rank}`).join(", ");
    const tip = `${m.name} takes ${prof} (skill 20 places the ${it.name}).` + (ups ? `\nHigher skill places ${ups}: same buff, plus their extras.` : "") +
      (SECONDARY.has(it.skill) ? `\n${prof} is a secondary profession: it doesn't use up one of the two primary ones.` : "");
    return el("li", { tabindex: 0, "data-tip": tip }, ...who, " → ", icon(it.icon, "", 18), " ", it.name, " ",
      el("span", { class: "muted" }, `(${prof} 20${SECONDARY.has(it.skill) ? ", secondary" : ""})`));
  });
  const [kit, rank] = FIRE_COOKING[state.fire];
  const cooks = members.filter((m) => (m.profs || []).includes(185)).map((m) => m.name);
  rows.push(el("li", { tabindex: 0, "data-tip": "Basic Campfire Kit (Cooking 1) holds 3 features, Journeyman (Cooking 140) 5, Expert (Cooking 220) 10.\nThe fire lasts 15 minutes; so does every feature placed at it." }, icon("inv_camelot_camping_welcomingcampfire", "", 18), " The fire: ", kit, " ",
    el("span", { class: "muted" }, cooks.length ? `(Cooking ${rank}: ${cooks.join(", ")})` : `(anyone with Cooking ${rank}; Cooking is secondary)`)));
  rows.push(el("li", { class: "muted" }, "First Aid, Fishing and Cooking are secondary professions: anyone can add them to their two primary ones."));
  $("profs").replaceChildren(...rows);
}

// ------------------------------------------------------------------ saved groups (this browser)
function readSaved() {
  try { return JSON.parse(localStorage.getItem(SAVED) || "[]").filter((s) => s && s.name && Array.isArray(s.roster)); }
  catch { return []; }
}
function writeSaved(list) {
  try { localStorage.setItem(SAVED, JSON.stringify(list)); return true; } catch { return false; }
}
function renderSaved() {
  const list = readSaved();
  $("saved").replaceChildren(...list.map((s, i) => el("li", { class: "chip" },
    el("button", { type: "button", class: "chip-load", "data-tip": `Load ${s.name}: ${s.roster.map((e) => CLASS_NAME(e.class) + " " + e.level).join(", ")}`, onclick: () => {
      state = { ...state, roster: structuredClone(s.roster), goal: s.goal || state.goal, fire: s.fire || state.fire,
        uptime: s.uptime ?? state.uptime };
      render();
    } }, s.name, el("span", { class: "muted" }, " " + s.roster.length)),
    el("button", { type: "button", class: "chip-x", "aria-label": "Delete " + s.name, onclick: () => {
      const l = readSaved(); l.splice(i, 1); writeSaved(l); renderSaved();
    } }, "×"))));
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

function render() {
  const members = M.planMembers(state.roster);
  const names = members.map((m) => m.name);
  $("count").textContent = `${state.roster.length} / ${PLAN_MAX}`;
  $("members").replaceChildren(...state.roster.map((e, i) => memberRow(e, i, names)));
  for (const b of document.querySelectorAll("#goal button")) b.setAttribute("aria-pressed", String(b.dataset.v === state.goal));
  for (const b of document.querySelectorAll("#fire button")) b.setAttribute("aria-pressed", String(+b.dataset.v === state.fire));
  $("uptime").value = state.uptime;
  $("uptime-out").textContent = state.uptime + "%";
  const code = save();
  if (document.activeElement !== $("code")) $("code").value = code;

  if (!members.length) {
    $("camp").replaceChildren(el("li", { class: "empty" }, "Add members above to see their camp."));
    $("profs").replaceChildren();
    $("notes").replaceChildren();
    $("grid").replaceChildren();
    $("pct").textContent = "0%";
    return;
  }
  const goal = resolvedGoal(members);
  const opts = { goal, uptime: state.uptime / 100, maxLevel: 60, seen: {}, cap: state.fire };
  const theory = M.theory(members, opts);
  const plan = M.planWithCamp(members, theory.lines, opts);
  const level = Math.max(...members.map((m) => m.level));
  $("pct").textContent = Math.round(plan.pct * 100) + "%";
  $("camp").replaceChildren(...(theory.lines.length
    ? theory.lines.map((line) => campCard(line, level, members))
    : [el("li", { class: "empty" }, "The group's class buffs already cover everything a camp could add.")]));

  // notes: blessings, the totem, what else would help
  const notes = [];
  const by = {};
  for (const m of members) for (const b of plan.bless[m.key] || []) (by[b] ||= []).push(m.name);
  if (Object.keys(by).length) {
    notes.push(el("p", { tabindex: 0, "data-tip": "Each paladin gives every class one blessing. Each member gets the blessing whose camp copy is weakest or missing, and the camp covers the rest." }, el("strong", {}, "Blessings "), ...Object.entries(by).flatMap(([b, who], i) => [
      i ? "; " : "", icon(D.class[b].icon, "", 16), " ", D.class[b].name, " → ", who.join(", ")])));
  }
  if (plan.totem) {
    notes.push(el("p", { tabindex: 0, "data-tip": "A shaman has one earth totem at a time. With a Sharpening Wheel down, the earth slot is free for Stoneskin or Tremor at little cost. Set the uptime on the left." }, el("strong", {}, "Totem "), icon(D.class.str.icon, "", 16),
      ` Strength of Earth ~${Math.round(plan.totem.soe)} Str at ${state.uptime}% uptime, a Sharpening Wheel ${plan.totem.wheel}.`));
  }
  if (plan.need.length) {
    notes.push(el("p", { tabindex: 0, "data-tip": "These would still add something, but the fire is full or everyone already places one feature an hour." }, el("strong", {}, "Also useful "), ...plan.need.slice(0, 3).flatMap((n, i) => [
      i ? ", " : "", icon(M.CAMP_ITEM[n.line].icon, "", 16), " ", M.CAMP_NAME[n.line]]),
      el("span", { class: "muted" }, " (with a bigger fire or more people)")));
  }
  notes.push(el("p", { class: "muted" }, goal === "level"
    ? "Planning for leveling: rested XP from a Camp Tent counts; mana and spirit weigh more."
    : "Planning for progression: power only; the tent counts for nothing."));
  $("notes").replaceChildren(...notes);
  renderProfs(members, theory);

  // the grid
  const head = el("tr", {}, el("th", { scope: "col" }, ""), ...members.map((m) =>
    el("th", { scope: "col", tabindex: 0, "data-tip": `${m.name}: ${m.role}, level ${m.level}` },
      el("img", { src: CLASS_ICON(m.class), alt: "", width: 18, height: 18 }), el("span", { class: "gname" }, m.name))));
  const rows = LINES.map((line) => el("tr", {},
    el("th", { scope: "row", tabindex: 0, "data-tip": line === "tent"
      ? "Rested XP: only the Camp Tent (Leatherworking) gives it."
      : `${LINE_NAME[line]}: the class buff ${D.class[line].name} (${CLASS_NAME(D.class[line].class)}) or the camp's ${M.CAMP_NAME[line]} (${PROFESSION[M.CAMP_ITEM[line].skill]}).` },
      icon(M.CAMP_ITEM[line].icon, "", 16), " ", LINE_NAME[line]),
    ...members.map((m) => {
      const c = plan.cells[m.key][line];
      if (!c || c.kind === "none") return el("td", {});
      const pct = Math.round((c.pct || 0) * 100);
      return el("td", { class: "k-" + c.kind, tabindex: 0, "data-tip": cellTip(m, line, c, plan) }, String(pct));
    })));
  $("grid").replaceChildren(el("thead", {}, head), el("tbody", {}, rows));
}

// ------------------------------------------------------------------ controls
for (const b of document.querySelectorAll("#goal button")) b.addEventListener("click", () => { state.goal = b.dataset.v; render(); });
for (const b of document.querySelectorAll("#fire button")) b.addEventListener("click", () => { state.fire = +b.dataset.v; render(); });
$("uptime").addEventListener("input", (ev) => { state.uptime = +ev.target.value; render(); });
$("set-level").addEventListener("click", () => {
  const v = Math.max(1, Math.min(60, Math.round(+$("all-level").value || 60)));
  for (const e of state.roster) e.level = v;
  render();
});
$("preset5").addEventListener("click", () => { state.roster = structuredClone(DEFAULT.roster); render(); });
$("clear").addEventListener("click", () => { state.roster = []; render(); });
$("copy").addEventListener("click", async () => {
  try { await navigator.clipboard.writeText($("code").value); $("copy").textContent = "Copied"; }
  catch { $("code").select(); }
  setTimeout(() => { $("copy").textContent = "Copy"; }, 1500);
});
function load() {
  const got = importPlan($("code").value.trim());
  const err = $("code-error");
  if (!got || !got.roster.length) {
    err.textContent = "That isn't an S'mores plan code. Codes start with SM1:";
    err.hidden = false;
    return;
  }
  err.hidden = true;
  state.roster = got.roster;
  state.goal = got.goal || "auto";
  render();
}
$("load").addEventListener("click", load);
$("code").addEventListener("keydown", (ev) => { if (ev.key === "Enter") load(); });
$("code").addEventListener("input", () => { $("code-error").hidden = true; });

renderAddButtons();
renderSaved();
render();
