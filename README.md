# Talisman Pity

A REFramework script for Monster Hunter Wilds that stops the same talisman from dropping again and again. When a reward matches a talisman you already got several times recently, the script rewrites it into a different one you have not received in that period.

Quest clear opens a watch window. You claim the talisman on the reward screen and it goes to your box, which is when the script sees it. It works on any quest. If you sell the reward instead of claiming it, nothing happens.

> [!WARNING]
> Back up your save before using it. The script writes straight into the loaded save data. Use at your own risk.

## Key features

- Logs every talisman you receive from quest rewards, with a timestamp.
- Compares each new talisman against that log. Skills, levels and slots all have to match.
- Once you have received the same talisman a set number of times inside your chosen time window, the next copy is changed into another combination.
- Picks the replacement from talismans already in your equipment box, so it is always a valid combination. It prefers one you have not received in the window, and falls back to the least-seen one.
- Lets you add your own combinations to the pool through the config file.
- Shows the latest swaps in the REFramework menu.

## Requirements

- Monster Hunter Wilds (PC, Steam)
- [REFramework](https://github.com/praydog/REFramework) for Monster Hunter Wilds

## Installation

1. Install REFramework if you do not have it.
2. Copy `talisman_pity.lua` into `reframework/autorun/` in your game folder.
3. Start the game. Open the REFramework menu (Insert by default) and find **Talisman Pity**.

To uninstall, delete `talisman_pity.lua`. Your history and settings are in `reframework/data/talisman_pity.json`. Delete that file too if you want a clean start.

## Settings

- **Enable**: turns the script on or off.
- **Swap after this many repeats** (default 2): how many times you must already have received a talisman inside the window before the next copy is swapped.
- **Window in hours** (default 24): how far back the script looks. Set it to 0 to use "since midnight" instead.
- **Watch seconds after quest clear** (default 600): how long new talismans count as quest rewards after a clear.
- **Minimum skills to count** (default 2): talismans with fewer skills are ignored.
- **Watch all the time**: counts every new talisman, not only rewards after a clear. This also catches melding results. It can swap a meld you wanted, so leave it off unless you want that.
- **Clear history**: forgets everything received so far.

## Custom pool (optional)

Open `talisman_pity.json` and add entries to the `pool` list, each with the three skill values and a slot value:

```json
"pool": [ { "raw": [3001, 2002, 0], "slots": 3010 } ]
```

A skill value is level x 1000 plus the skill id. These combinations are only used as replacements.

## Compatibility

It is meant for single-player use. Do not use it in online or multiplayer sessions.

## Known issues

- The replacement pool comes from your own box. With very few talismans there may be nothing different to swap in, and the script then leaves the reward alone.
- The reward screen may still show the original talisman while the swapped one lands in your box. If that bothers you, check your box after claiming.
- The swap rewrites the talisman's skill and slot values. The game may still reject unusual combinations, so stick to combinations that exist on talismans the game gives out.

## Troubleshooting

- **Menu missing**: check that `talisman_pity.lua` sits in `reframework/autorun/` and that REFramework shows no script errors.
- **"Quest clear hook: NOT found"**: tick "Watch all the time" instead.
- **Nothing gets swapped**: you may not have hit the repeat count yet, or your box has no different talisman to use. Lower the repeat count or add entries to the custom pool.

## Credits

- [praydog](https://www.nexusmods.com/profile/praydog?gameId=6993), for REFramework.
- [DavidLight](https://www.nexusmods.com/profile/DavidLight?gameId=6993), for [Talisman Analyser](https://www.nexusmods.com/monsterhunterwilds/mods/4472), and [Ninull](https://www.nexusmods.com/profile/ninull?gameId=6993), for [Talisman Data Export (mhwilds.wiki-db.com)](https://www.nexusmods.com/monsterhunterwilds/mods/3652), whose decoders showed how talisman skills and slots are stored.
- [Paradyse19](https://www.nexusmods.com/profile/Paradyse19?gameId=6993), for [Bonus Quest Rewards](https://www.nexusmods.com/monsterhunterwilds/mods/921), whose quest clear hook this script follows.
