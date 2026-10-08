# S'mores

A camp planner for WoW Forever. It looks at your group and the camp items people carry, and works out who should
drop which camp feature, so the camp fills what your classes' buffs leave open. It also picks the paladins'
blessings and weighs a shaman's Strength of Earth against a Sharpening Wheel.

**S'mores Planner:** https://alcaras.github.io/smores/ plans any party or raid (up to 20) in the browser. Plans move
between the page and the game as short codes (`SM1:...`).

## Install

Download `Smores-<version>.zip` from [Releases](https://github.com/alcaras/smores/releases) and unzip it into
`World of Warcraft\_classic_beta_\Interface\AddOns`, so the folder `Smores` holds `Smores.toc`.

## Use

- `/smores` opens the panel (it also opens by itself next to a campfire when you're in a group).
- Each row: what that person should drop, what it gives, and ready / cooldown / placed. Everyone running S'mores
  shares their camp items, professions and cooldown, so the plan covers them too.
- The buttons by the title switch the plan between the party and you, and between leveling and progression.
- `/smores plan` makes up any group; `/smores demo` shows the panel with four made-up members.
- `/smores` alone lists every command.

See [Smores/README.md](Smores/README.md) for the details.

A test build: report what looks wrong in [Issues](https://github.com/alcaras/smores/issues), with a screenshot of the
panel and who was in the group.

World of Warcraft and its icons are Blizzard Entertainment's; the Planner shows the icons from Wowhead. A fan
project, not affiliated with Blizzard.
