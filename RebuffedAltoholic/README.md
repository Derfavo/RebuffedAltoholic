# RebuffedAltoholic

A character manager for the original WoW 3.3.5a client, build 12340. Keep your characters' inventories, professions and progress in one place, including items added by private servers.

This is an independent implementation. It does not contain Altoholic or DataStore code and does not require either addon.

## Open the window

Click the book icon next to the minimap or type `/ralt`. Drag the icon to move it around the minimap. Drag the window to move it; Escape closes it. The character selector and realm filter let you browse saved characters without logging between them.

`/ralt search item name` searches recorded possessions. An item ID also works. Search text is matched literally, so punctuation does not act as a pattern. Use the quality button to narrow item results.

## What is recorded

| Area | Contents |
| --- | --- |
| Summary | Character level, class, race, gold, experience, rested experience, bag usage and activity |
| Inventory | Bags, keyring, bank, bank bags and equipped items, with quantities and full item links |
| Mail | Visible mailbox messages, attached items, money and expiry dates |
| Auctions | Your auctions and bids when their pages are opened |
| Professions | Skill ranks, observed learned recipes, custom recipe outputs and reagents |
| Progress | Quests, reputations, talent groups, learned spells, mounts, companions, currencies and achievements |
| Equipment | Slot-by-slot lists, comparison with another recorded character and average equipped item level |
| Guild bank | Money and the bank tabs you have visited |
| Calendar | Recorded mail expiries and raid lockout resets |
| Search | Possessions across characters and guild banks, learned recipes and the observed item catalog |

Hover an item to view its tooltip. Normal item tooltips show which characters on the current realm have that item. Click an item to open its link; Shift-click inserts it into an active chat box. Right-click an equipped item to search the observed catalog for the same equipment type with a higher item level. This is an item-level comparison, not a recommendation for your specialization.

## Recording your characters

Log in to each character once. Open the bank, mailbox, profession windows and your auction/bid pages to record those contents. Visit each guild bank tab you want to keep. Expand quest, skill, reputation and currency categories to expose their entries. Profession filters can hide recipes; previously recorded recipes are kept when a filtered list is shown. Use `/played` if you also want to record total time played.

The window shows the last recorded state. Offline characters cannot update themselves. Mail expiry dates and raid reset times are calculated from the server's values at the time they are recorded. An expired entry does not prove that mail was collected or an auction sold.

## Custom items

There is no built-in WotLK item-ID whitelist. Actual links encountered in inventories, equipment, mail, auctions, guild bank tabs, recipes, vendor lists, loot and item tooltips are added to the catalog. Items do not need to exist in a standard WotLK loot table.

Each holding keeps its complete item link, including enchantments, gems and other link fields. Metadata is stored separately for each realm. If the client does not have an item's information yet, the holding is kept and the addon retries that observed link at a limited rate. Unanswered requests stop instead of running forever; encountering the item again later can retry it. A name contained in the item link remains visible while metadata is unavailable.

The addon cannot discover server items that the client has never encountered, invent missing item stats or list every custom boss drop. The known-items page is a catalog of observed items, not a complete loot database. Item-level comparisons need metadata supplied by the server/client.

## Sharing another account

Both players need RebuffedAltoholic on the same realm and must be online.

1. Request the other account with `/ralt request PlayerName`.
2. The other player approves with `/ralt accept YourPlayerName` within two minutes.
3. Keep both characters online until the transfer finishes.

Approval shares the saved characters on that realm, including inventory, mail headers, gold and progress. Transfers are paced and can take several minutes for a large account. Imported characters are labeled with the sender and do not replace local characters. The transfer stops if the recipient goes offline. No character data is shared automatically at login.

## Performance and compatibility

Inventory changes are combined into short delayed updates. Bank, mail and auction scans run while those sources are accessible. Achievements are collected in batches. Item lookups use a bounded queue of observed links. The work scheduler removes its update handler when there is no pending work. Minimap dragging only uses an update handler during the drag.

The tooltip extension does not repeatedly reopen tooltips. No foreign talent inspections are used. Personal character information stays in `RebuffedAltoholicDB` unless you explicitly approve an account transfer.

## Installation and updates

Copy the `RebuffedAltoholic` folder into `Interface/AddOns`, then restart WoW. This addon is for the original 3.3.5a client, not Wrath Classic or Retail.

Update notices follow the same in-game version exchange as the other Rebuffed addons. A newer release must be reported by two different players before a notice is shown. `/rebuffedupdates` displays installed versions and confirmed updates. Downloads and installation remain manual.
