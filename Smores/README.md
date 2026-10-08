# S'mores

A camp planner for WoW Forever. It looks at your group and the camp items people carry, and works out who should
drop which camp feature so the camp fills what your classes' buffs leave open.

- Class buffs beat their camp copies (a camp buff is 64-81% of the class buff), so it never plans a First Aid Kit
  next to a priest's Fortitude.
- With a paladin it picks the blessings too: each class gets the blessing whose camp copy is weakest or missing
  (Might for melee when nobody has a Lodestone, while a Fish Bowl covers Kings).
- With a shaman it shows Strength of Earth (at 70% uptime) next to a Sharpening Wheel, so the shaman can judge the
  earth slot.

## Use

- `/smores` opens or closes the panel. It also opens by itself next to a campfire when you're in a group.
- One row per member: what to drop, what it gives, and ready / cooldown / placed.
- Need: buffs that would help but nobody in the group carries. Skip: camp items a class buff already beats.
- Best: what someone should drop if they carried the best item their professions allow (it's not in their bags).
  The footer shows both: "Covers 72%, 85% with best items".
- Grid: the coverage per member and buff (blue = class buff, green = camp copy as % of the class buff, red = missing).
  Click a member's role to change it (tank, melee, ranged, caster, healer).
- The two buttons next to the title switch what the plan is for: Party (the whole group) or You (your class and
  role only), and Leveling (rested XP from a Camp Tent counts, mana and spirit weigh more) or Progression (power
  only). By default it plans for leveling below the level cap and for progression at it.
- Theory: the best set of camp features for this group if professions didn't matter (and an Expert fire).
  The footer shows all three: "Now 72% / best items 85% / theory 92%".
- Post to group: one line in party or raid chat with the plan.
- `/smores demo` shows the panel with you and four made-up members at your level (`demo paladin` for a
  group with a paladin, `demo off` to stop); nothing is sent while it is on.
- `/smores goal leveling | progress | auto` and `/smores for party | you` do the same as the buttons.
- `/smores uptime 70` sets how often totems count as up; `/smores auto off` stops it opening by itself;
  `/smores reset` puts the panel back.

Everyone who runs S'mores shares their camp items and cooldown with the group, so the plan covers them too. Without
it, a player still gets the buffs, but the planner can't see their bags.

## Plan mode

`/smores plan` plans any party or raid (up to 20) you make up, starting from your current group. Click a name to
change the class, click the role to change it, x removes, + Add adds. The panel shows the best camp for that roster
(ignoring professions) and who gets which blessing. `/smores plan warrior rogue mage priest paladin` sets a whole
roster; `/smores plan level 45` sets everyone's level; `/smores plan off` goes back.

The S'mores Planner (https://alcaras.github.io/smores/) does the same in a browser. Code shows the plan as a short code (`SM1:P:WAt60,ROm60,...`): copy it to share or to open it on the companion site,
or paste a code there and press Enter (`/smores import <code>` works too).

## Install

Unzip into `World of Warcraft\_classic_beta_\Interface\AddOns` (the folder `Smores` with `Smores.toc` inside).
New versions: https://github.com/alcaras/smores/releases

Version 0.2.0, a test build. Report what looks wrong, with a screenshot of the panel.
