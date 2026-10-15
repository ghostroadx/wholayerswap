# WhoLayerSwap

A World of Warcraft: Forever addon for swapping layers by swapping between three language guilds:

| Button | Guilds (built in) | Phrase typed in the swap channel |
|---|---|---|
| English | `<Who>`, `<Who Two>` | `LayerSwap English` |
| Latam | `<Quien>`, `<Quien Two>` | `LayerSwap Latam` |
| Portuguese | `<Quem>`, `<Quem Two>` | `LayerSwap Portuguese` |

On Forever, guild membership is one of the things the server uses to place you on a layer when you log in. Joining the guild that matches a language, then relogging, is a quick way onto that group's layer.

## Install

1. Download this repo (**Code → Download ZIP**).
2. Copy the `WhoLayerSwap` folder into `World of Warcraft\_classic_beta_\Interface\AddOns\` (the Forever beta folder; it may be renamed at launch).
3. Fully restart the game. `/reload` doesn't pick up new addon folders.

Everyone in the guilds needs the addon: the people asking for an invite, and the members who send invites.

## How it works

**Swapping.** The **Layer swap** panel (next to the minimap; drag it to move) has English, Latam and Portuguese buttons. Clicking one:

1. leaves your current guild (`/gquit`),
2. types the language's phrase in the hidden swap channel,
3. and, once someone from the matching guild invites you, accepts automatically and shows **"Relog to change layers"**.

Your current guild's button is greyed out. If you're in a guild that isn't one of these, the button asks you to `/gquit` yourself first, so you can't leave a real guild by accident. Guild leaders are told to pass leadership first.

**Inviting.** Members of the matching guild get each request in their **Invite queue**, a small list under the Layer swap panel (drag it anywhere):

- one row per person, with a 20-second countdown and its own **Invite** button (right-click to skip);
- a row disappears when you invite that person, when their 20 seconds run out, or when a guildmate invites them first, across both guilds of a pair (Who and Who Two);
- rows keep their place, so nothing shifts under your mouse; with more than 8 people waiting it shows "+N more waiting" and fills rows as they free up;
- a quiet ping at most every 8 seconds (can be turned off), and no chat line per request.

**Guild Charter.** While you carry a Guild Charter, a big **Guild Charter** button appears just below the middle of the screen, and **F1** does the same (per character, only while you carry the charter; your own key bindings aren't changed):

1. Press F1 (or click) to open the charter.
2. Target a player and press F1 again: they get a whisper ("Forming a guild, mind signing and you can quit later?") and a signature request.
3. Target the next person and repeat. People who already signed are skipped, and the same person isn't whispered twice within 30 seconds.

Handy for founding a backup guild.

**Whispers.** Whispering a member `ginv` also puts you in their invite queue.

**Swap channel.** Everyone with the addon joins `whoguildlayerswapchannel` a few seconds after login. It's hidden from chat by default.

## Settings

Open them with the gear on the panel, right-click the panel, `/wls settings`, or Options → AddOns → WhoLayerSwap.

- **Guild names**: the built-in names always work. Add extra names for a language (comma-separated, up to 5) if a guild has to be refounded under another name.
- **Invite queue**: move it, or reset it to under the Layer swap panel.
- **General**: auto-accept, show the swap channel in chat (off by default), lock the panel, the Guild Charter button, F1 for the charter (this character), debug messages, the queue ping.

## Commands

| Command | What it does |
|---|---|
| `/wls` | Status: swap channel, your guild, whether you can invite |
| `/wls settings` | Open settings |
| `/wls guild latam Los Quien, Quien Tres` | Set extra guild names for a language |
| `/wls movequeue` | Move the invite queue |
| `/wls charter` | Turn the Guild Charter button on or off |
| `/wls charterkey` | Turn F1 for the charter on or off (this character) |
| `/wls charterwhisper <text>` | Change the signature whisper (no text = default) |
| `/wls showchannel` | Show or hide the swap channel in chat |
| `/wls accept` | Turn auto-accept on or off |
| `/wls show`, `hide`, `lock`, `reset` | Panel visibility, lock and position |
| `/wls phrases` | List the phrases and guilds |
| `/wls debug` | Explain why each request was or wasn't invited |

## Why it works this way (Forever restrictions)

- **Leaving a guild** (`/gquit`) and **sending a guild invite** (`/ginvite`) are Blizzard-only actions. Addons calling them are blocked ("Interface action failed because of an AddOn"). So the swap and invite buttons are secure macro buttons: your click runs the command as if you typed it.
- Secure buttons can't change during combat, so the invite queue, the charter button and F1 only update out of combat, and the panels can't be moved mid-fight.
- Chat is hidden from addons during chat lockdown (boss fights, rated PvP), so requests then are skipped.
- Party invites don't help: leaving a group sends you straight back to your own layer. Guild plus relog does.
- Forever's beta doesn't always load saved addon settings back after a relog, so custom settings may reset until Blizzard fixes it.

## Tests

`tests/` runs the real addon against a mock Forever client (timers, combat lockdown, secure buttons, chat, guilds, bags) and checks 340 cases: request routing, look-alike guilds and channels, the invite queue (timing, slots, 20 people at once), invite claims, auto-accept, the swap buttons, settings and the Guild Charter button. The mock blocks the same things the game blocks in combat, so a protected change mid-fight fails the tests.

```
pip install lupa
python3 tests/test_wholayerswap.py
```

Every game function the addon calls was checked against Blizzard's Forever UI source (the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source), build 1.60.1).
