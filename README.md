# Can I Craft?

A World of Warcraft addon that shows which recipes you could craft if you bought the vendor reagents first (Salt, Thread, Dye, Flux, Vials, and so on), or crafted the intermediate parts first (like Cured Hides).

When you open a profession window, each recipe gets a `[n]` count. That number is how many you could make, counting reagents you could buy from a vendor and parts you could craft yourself.

## Installation

1. Click the green **Code** button on this page and choose **Download ZIP**.
2. Unzip it. Inside the `CanICraft-main` folder there's a folder named **`CanICraft`**.
3. Copy that `CanICraft` folder into your WoW AddOns folder:
   ```
   <WoW install folder>/Interface/AddOns/
   ```
   You should end up with `Interface/AddOns/CanICraft/CanICraft.toc`.
   Don't copy the outer `CanICraft-main` folder: WoW won't load the addon that way.
4. Restart WoW, or type `/reload` if you're already in game. Check that **Can I Craft?** is turned on in the AddOns list on the character select screen.

## How it works

- The addon starts with a list of common vendor reagents.
- Each time you open a vendor, it records every item that vendor sells in unlimited supply, along with its price. Items you buy from vendors are then counted automatically.
- It looks up to 4 levels deep for parts you could craft first.

## Commands

| Command | What it does |
|---|---|
| `/cic add <item>` | Mark a reagent as vendor-bought |
| `/cic remove <item>` | Stop treating a reagent as vendor-bought |
| `/cic list` | Show known vendor reagents and their prices |
| `/cic bank` | Toggle counting items in your bank |
| `/cic toggle` | Turn the `[n]` counts on or off |
| `/cic dump` | Print the selected recipe's reagents (for bug reports) |
| `/cic debug` | Show what the addon could hook into |

`/canicraft` works the same as `/cic`.
