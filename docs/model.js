// S'mores model for the companion site: a line-by-line port of addons/Smores/Model.lua (plan mode: Theory and
// Plan with a given camp) plus the plan code. test/run_smores_site.py checks it gives the addon's answers.

export const LINES = ["sta", "motw", "kings", "str", "ap", "mp5", "spi", "int", "crit", "tent"];
export const LINE_NAME = {
  sta: "Stamina", motw: "Armor, stats", kings: "Stats %", str: "Strength", ap: "Melee AP", mp5: "Mana / 5",
  spi: "Spirit", int: "Intellect", crit: "Crit", tent: "Rested XP",
};
export const BLESSINGS = ["kings", "ap", "mp5"];
export const ROLES = ["tank", "melee", "ranged", "caster", "healer"];
export const CLASSES = ["WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "SHAMAN", "PALADIN"];
export const PLAN_MAX = 20;

const WEIGHTS = {
  tank: { sta: 1.0, armor: 0.05, str: 0.6, agi: 0.6, int: 0, spi: 0, ap: 0.15, mp5: 0, crit: 6, res: 0.1 },
  melee: { sta: 0.3, armor: 0.01, str: 1.0, agi: 1.0, int: 0, spi: 0, ap: 0.5, mp5: 0, crit: 20, res: 0.05 },
  ranged: { sta: 0.3, armor: 0.01, str: 0, agi: 1.0, int: 0.4, spi: 0.1, ap: 0, mp5: 1.0, crit: 20, res: 0.05 },
  caster: { sta: 0.3, armor: 0.01, str: 0, agi: 0, int: 1.0, spi: 0.4, ap: 0, mp5: 2.0, crit: 12, res: 0.05 },
  healer: { sta: 0.3, armor: 0.01, str: 0, agi: 0, int: 1.0, spi: 0.7, ap: 0, mp5: 2.5, crit: 6, res: 0.05 },
};
const REST = { level: 60, progress: 0 };
const BOOST = { level: { mp5: 1.5, spi: 1.5, sta: 1.2 }, progress: {} };
const DEFAULT_ROLE = {
  WARRIOR: "melee", ROGUE: "melee", HUNTER: "ranged", MAGE: "caster", WARLOCK: "caster",
  PRIEST: "healer", DRUID: "healer", SHAMAN: "healer", PALADIN: "healer",
};
export const defaultRole = (cls) => DEFAULT_ROLE[cls] || "melee";

export function makeModel(D) {
  const CAMP_NAME = {};
  const CAMP_ITEM = {};
  for (const [id, it] of Object.entries(D.items)) {
    if (it.tier === 1 && it.line) { CAMP_NAME[it.line] = it.name; CAMP_ITEM[it.line] = { id: +id, ...it }; }
  }

  const step = (steps, level) => {
    let v = 0;
    for (const s of steps) { if (level >= s[0]) v = s[1]; else break; }
    return v;
  };
  const amounts = (entry, level) => {
    const out = {};
    for (const [comp, steps] of Object.entries(entry.comp)) out[comp] = step(steps, level);
    return out;
  };
  const campAmounts = (line, level) => amounts(D.camp[line], level);
  const classAmounts = (line, level) => amounts(D.class[line], level);
  const estStat = (level) => 2 * level + 20;

  function worth(role, level, amts, goal) {
    const w = WEIGHTS[role] || WEIGHTS.melee;
    const b = BOOST[goal || "progress"] || BOOST.progress;
    const all = w.str + w.agi + w.sta * (b.sta || 1) + w.int + w.spi * (b.spi || 1);
    let v = 0;
    for (const [comp, x] of Object.entries(amts)) {
      if (comp === "stat") v += x * all;
      else if (comp === "res") v += x * w.res * 5;
      else if (comp === "pct") v += x / 100 * estStat(level) * all;
      else v += x * (w[comp] || 0) * (b[comp] || 1);
    }
    return v;
  }

  function prepare(members, opts) {
    const best = {};
    let paladins = 0;
    const talentBy = {};
    for (const m of members) {
      best[m.class] = Math.max(best[m.class] || 0, m.level);
      if (m.class === "PALADIN") paladins++;
      for (const line of Object.keys(m.talents || {})) talentBy[line] = Math.max(talentBy[line] || 0, m.level);
    }
    const seen = opts.seen || {};
    const goal = opts.goal || "progress";
    const info = { paladins, subsets: [], kings: false, focus: opts.focus };
    if (paladins > 0 && (talentBy.kings || seen.kings)) info.kings = true;
    const avail = BLESSINGS.filter((b) => b !== "kings" || info.kings);
    const n = avail.length;
    for (let mask = 0; mask < 2 ** n; mask++) {
      const set = [];
      for (let i = 0; i < n; i++) if (mask & (1 << i)) set.push(avail[i]);
      if (set.length <= paladins) info.subsets.push(set);
    }
    for (const m of members) {
      const p = { base: {}, camp: {}, full: {}, bless: {} };
      for (const line of LINES) {
        if (line === "tent") {
          const v = m.level < (opts.maxLevel || 60) ? REST[goal] : 0;
          p.camp[line] = v; p.full[line] = v; p.base[line] = 0;
          continue;
        }
        p.camp[line] = worth(m.role, m.level, campAmounts(line, m.level), goal);
        p.full[line] = Math.max(worth(m.role, m.level, classAmounts(line, m.level), goal), p.camp[line]);
        const c = D.class[line];
        let base = 0;
        if (c.kind === "all" && best[c.class]) {
          base = worth(m.role, m.level, classAmounts(line, best[c.class]), goal);
        } else if (c.kind === "talent" && (talentBy[line] || seen[line])) {
          base = worth(m.role, m.level, classAmounts(line, talentBy[line] || best[c.class] || m.level), goal);
        } else if (c.kind === "totem" && best[c.class]) {
          base = worth(m.role, m.level, classAmounts(line, best[c.class]), goal) * (opts.uptime ?? 0.7);
        } else if (c.kind === "blessing" && best.PALADIN && (line !== "kings" || info.kings)) {
          p.bless[line] = worth(m.role, m.level, classAmounts(line, best.PALADIN), goal);
        }
        p.base[line] = base;
      }
      m._p = p;
    }
    return info;
  }

  function memberScore(m, camp, info) {
    const p = m._p;
    let total = 0;
    for (const line of LINES) {
      if (p.bless[line] === undefined) total += Math.max(p.base[line], camp[line] ? p.camp[line] : 0);
    }
    if (info.paladins === 0) return [total, null];
    let bestV = -1, bestSet = null;
    for (const set of info.subsets) {
      let v = 0;
      for (const b of BLESSINGS) {
        if (p.bless[b] !== undefined) {
          const given = set.includes(b);
          v += Math.max(given ? p.bless[b] : 0, camp[b] ? p.camp[b] : 0);
        }
      }
      if (v > bestV + 1e-9) { bestV = v; bestSet = set; }
    }
    return [total + Math.max(bestV, 0), bestSet];
  }

  function score(members, camp, info) {
    let s = 0;
    for (const m of members) if (!info.focus || m.key === info.focus) s += memberScore(m, camp, info)[0];
    return s;
  }

  // Lines -> members (each member places at most one; m.can = the lines their professions place, none = any),
  // or null when the group can't place them all. Members with set professions are tried first.
  function assign(members, lines) {
    const order = members.map((m, i) => i).sort((a, b) => (members[a].can ? 0 : 1) - (members[b].can ? 0 : 1));
    const owner = {};   // member index -> line
    const lineOf = {};  // line -> member index
    const canPlace = (i, line) => !members[i].can || members[i].can.includes(line);
    const tryLine = (line, seen) => {
      for (const i of order) {
        if (!canPlace(i, line) || seen.has(i)) continue;
        seen.add(i);
        if (owner[i] === undefined || tryLine(owner[i], seen)) { owner[i] = line; lineOf[line] = i; return true; }
      }
      return false;
    };
    for (const line of lines) if (!tryLine(line, new Set())) return null;
    for (const [i, line] of Object.entries(owner)) lineOf[line] = +i;
    return lineOf;
  }

  // the best set of lines, at most `cap` (default min(10, members)), that the group can place: ignoring
  // professions, except for members whose professions are set (m.can)
  function theory(members, opts = {}) {
    const copies = members.map((m) => ({ ...m, _p: undefined }));
    const info = prepare(copies, opts);
    const n = LINES.length;
    const k = Math.min(opts.cap || 10, copies.length);
    const constrained = copies.some((m) => m.can);
    let bestS = -1, bestMask = 0, bestAssign = null;
    const camp = {};
    for (let mask = 0; mask < 2 ** n; mask++) {
      let size = 0;
      for (let i = 0; i < n; i++) {
        if (mask & (1 << i)) { camp[LINES[i]] = true; size++; } else delete camp[LINES[i]];
      }
      if (size <= k) {
        const s = score(copies, camp, info);
        if (s > bestS + 1e-6) {
          const a = constrained ? assign(copies, Object.keys(camp)) : {};
          if (a) { bestS = s; bestMask = mask; bestAssign = a; }
        }
      }
    }
    const lines = LINES.filter((_, i) => bestMask & (1 << i));
    let full = 0;
    for (const c of copies) {
      if (!info.focus || c.key === info.focus) for (const line of LINES) full += c._p.full[line];
    }
    return { lines, pct: full > 0 ? bestS / full : 0, assign: constrained ? bestAssign : assign(copies, lines) };
  }

  // the plan for a given camp (lines): blessings, cells, coverage, what else would help, the totem note
  function planWithCamp(members, lines, opts = {}) {
    const info = prepare(members, opts);
    const camp = {};
    for (const l of lines) camp[l] = "theory";
    const plan = { camp, bless: {}, cells: {}, need: [], used: lines.length, goal: opts.goal || "progress" };
    plan.score = score(members, camp, info);
    let full = 0;
    for (const m of members) {
      const [, set] = memberScore(m, camp, info);
      plan.bless[m.key] = set;
      const given = new Set(set || []);
      const p = m._p, row = {};
      const counted = !info.focus || m.key === info.focus;
      for (const line of LINES) {
        const f = p.full[line];
        if (counted) full += f;
        const cls = Math.max(p.base[line], given.has(line) ? p.bless[line] : 0);
        const c = camp[line] ? p.camp[line] : 0;
        if (f <= 0) row[line] = { kind: "none" };
        else if (cls > 0 && cls >= c) row[line] = { kind: "class", pct: cls / f };
        else if (c > 0) row[line] = { kind: "camp", pct: c / f };
        else row[line] = { kind: "missing", pct: 0 };
      }
      plan.cells[m.key] = row;
    }
    plan.full = full;
    plan.pct = full > 0 ? plan.score / full : 0;
    for (const line of LINES) {
      if (camp[line]) continue;
      camp[line] = "?";
      const g = score(members, camp, info) - plan.score;
      delete camp[line];
      if (g > 0.5) plan.need.push({ line, gain: g });
    }
    plan.need.sort((a, b) => b.gain - a.gain);
    if (camp.str) {
      const sh = members.find((m) => m.class === "SHAMAN");
      if (sh) plan.totem = { soe: classAmounts("str", sh.level).str * (opts.uptime ?? 0.7), wheel: campAmounts("str", sh.level).str };
    }
    return plan;
  }

  // a planned roster -> members (planned paladins have Kings, priests Divine Spirit, caster druids Moonkin)
  function planMembers(roster) {
    const count = {};
    return roster.map((e, i) => {
      const base = e.class[0] + e.class.slice(1).toLowerCase();
      count[base] = (count[base] || 0) + 1;
      const named = (e.name || "").trim();
      const m = {
        key: "p" + (i + 1), name: named || (count[base] > 1 ? `${base} ${count[base]}` : base), class: e.class,
        level: e.level || 60, role: e.role || defaultRole(e.class), talents: {}, planIndex: i,
      };
      if (e.profs && e.profs.length) {
        m.profs = e.profs;
        m.can = LINES.filter((line) => CAMP_ITEM[line] && e.profs.includes(CAMP_ITEM[line].skill));
      }
      for (const [line, c] of Object.entries(D.class)) {
        if ((c.kind === "talent" || line === "kings") && c.class === m.class && (line !== "crit" || m.role === "caster")) {
          m.talents[line] = true;
        }
      }
      return m;
    });
  }

  function gives(line, level) {
    if (line === "tent") return "rested XP";
    const a = campAmounts(line, level);
    if (line === "motw") return `+${a.armor || 0} armor` + ((a.stat || 0) > 0 ? `, +${a.stat} stats` : "");
    if (line === "kings") return `+${a.pct || 0}% stats`;
    if (line === "crit") return `+${a.crit || 0}% crit`;
    const unit = { sta: "Sta", str: "Str", ap: "AP", mp5: "mp5", spi: "Spi", int: "Int" }[line];
    const v = Object.values(a)[0] || 0;
    return `+${v} ${unit}`;
  }

  return { theory, planWithCamp, planMembers, gives, campAmounts, classAmounts, CAMP_NAME, CAMP_ITEM, step, assign };
}

// ------------------------------------------------------------------ the plan code (same as the addon)
const CLASS_CODE = { WARRIOR: "WA", ROGUE: "RO", HUNTER: "HU", MAGE: "MA", WARLOCK: "WL", PRIEST: "PR", DRUID: "DR", SHAMAN: "SH", PALADIN: "PA" };
const CODE_CLASS = Object.fromEntries(Object.entries(CLASS_CODE).map(([c, k]) => [k, c]));
const ROLE_CODE = { tank: "t", melee: "m", ranged: "r", caster: "c", healer: "h" };
const CODE_ROLE = Object.fromEntries(Object.entries(ROLE_CODE).map(([r, k]) => [k, r]));
// professions in a plan code: skill line -> two letters (upper, lower)
export const PROF_CODE = { 171: "Al", 164: "Bs", 333: "En", 202: "Eg", 182: "He", 165: "Lw", 186: "Mi", 393: "Sk", 197: "Ta",
  185: "Co", 129: "Fa", 356: "Fi" };
const CODE_PROF = Object.fromEntries(Object.entries(PROF_CODE).map(([s, k]) => [k, +s]));

// a name as it can travel in a code: no separators, no spaces, at most 24 characters
export const cleanName = (n) => (n || "").replace(/[\s,~:#-]+/g, "").slice(0, 24);

export function exportPlan(roster, goal) {
  const g = goal === "level" ? "L" : goal === "progress" ? "P" : "A";
  return `SM1:${g}:` + roster.map((e) => (CLASS_CODE[e.class] || "WA") + (ROLE_CODE[e.role] || "m") + Math.floor(e.level || 60)
    + (e.profs && e.profs.length ? "-" + e.profs.map((p) => PROF_CODE[p] || "").join("") : "")
    + (cleanName(e.name) ? "~" + cleanName(e.name) : "")).join(",");
}

export function importPlan(text) {
  const m = /(?:SM1|CW1):([LPA]):(\S*)/u.exec(text || "");   // CW1: from when it was called Campwise
  if (!m) return null;
  const roster = [];
  for (const [, code, role, level, profs, name] of m[2].matchAll(/([A-Z]{2})([a-z])(\d+)(?:-((?:[A-Z][a-z])*))?(?:~([^,~]*))?/gu)) {
    const cls = CODE_CLASS[code];
    if (cls && roster.length < PLAN_MAX) {
      const e = { class: cls, role: CODE_ROLE[role] || defaultRole(cls), level: Math.max(1, Math.min(60, +level)) };
      const p = [...(profs || "").matchAll(/[A-Z][a-z]/g)].map((x) => CODE_PROF[x[0]]).filter(Boolean);
      if (p.length) e.profs = [...new Set(p)];
      if (cleanName(name)) e.name = cleanName(name);
      roster.push(e);
    }
  }
  return { roster, goal: m[1] === "L" ? "level" : m[1] === "P" ? "progress" : null };
}
