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

**Inviting.** Members of the matching guild hear a ping and get a glowing **Invite \<name\>** button in the middle of the screen. Left-click invites, right-click skips. Whoever clicks first wins; everyone else's button clears, across both guilds of a pair (Who and Who Two).

**Guild Charter.** While you carry a Guild Charter, a **Guild Charter** button appears under the panel. Click it to open the charter, or target a player first to ask them to sign it. Handy for founding a backup guild.

**Whispers.** Whispering a member `ginv` also puts you on their Invite button.

**Swap channel.** Everyone with the addon joins `whoguildlayerswapchannel` a few seconds after login. It's hidden from chat by default.

## Settings

Open them with the gear on the panel, right-click the panel, `/wls settings`, or Options → AddOns → WhoLayerSwap.

- **Guild names**: the built-in names always work. Add extra names for a language (comma-separated, up to 5) if a guild has to be refounded under another name.
- **Invite button**: drag it anywhere, or reset it to the middle of the screen.
- **General**: auto-accept, show the swap channel in chat, lock the panel, the Guild Charter button, debug messages.

## Commands

| Command | What it does |
|---|---|
| `/wls` | Status: swap channel, your guild, whether you can invite |
| `/wls settings` | Open settings |
| `/wls guild latam Los Quien, Quien Tres` | Set extra guild names for a language |
| `/wls moveinvite` | Move the invite button |
| `/wls charter` | Turn the Guild Charter button on or off |
| `/wls showchannel` | Show or hide the swap channel in chat |
| `/wls accept` | Turn auto-accept on or off |
| `/wls show`, `hide`, `lock`, `reset` | Panel visibility, lock and position |
| `/wls phrases` | List the phrases and guilds |
| `/wls debug` | Explain why each request was or wasn't invited |

## Why it works this way (Forever restrictions)

- **Leaving a guild** (`/gquit`) and **sending a guild invite** (`/ginvite`) are Blizzard-only actions. Addons calling them are blocked ("Interface action failed because of an AddOn"). So the swap and invite buttons are secure macro buttons: your click runs the command as if you typed it.
- Secure buttons can't change during combat, so the invite button appears, and the panel moves, only out of combat.
- Chat is hidden from addons during chat lockdown (boss fights, rated PvP), so requests then are skipped.
- Party invites don't help: leaving a group sends you straight back to your own layer. Guild plus relog does.
- Forever's beta doesn't always load saved addon settings back after a relog, so custom settings may reset until Blizzard fixes it.

## Tests

`tests/` runs the real addon against a mock Forever client (timers, combat lockdown, secure buttons, chat, guilds, bags) and checks about 300 cases: request routing, look-alike guilds and channels, invite claims, auto-accept, the swap buttons, settings and the Guild Charter button.

```
pip install lupa
python3 tests/test_wholayerswap.py
```

Every game function the addon calls was checked against Blizzard's Forever UI source (the `forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source), build 1.60.1).
