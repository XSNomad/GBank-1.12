GBankKronos112
===============

Fake guild bank viewer for Vanilla 1.12 servers such as Kronos.

This is not a real guild bank. Vanilla 1.12 has no guild bank backend.
This addon scans bank alts, saves a cached snapshot, and lets guild members
view/search the last synced snapshot in game.

Install
-------
Put this folder here:

World of Warcraft\Interface\AddOns\GBankKronos112\

The folder must contain:

GBankKronos112.toc
GBankKronos112.lua
README.txt

Commands
--------
/gbank
Open or close the viewer.

/gbank scan [name]
Scan current character bags. If the bank is open, scans bank and bank bags too.
If mailbox is open, scans mail attachments too.
Use name to label the bank alt or category, for example:
/gbank scan LEVELUPraid
/gbank scan LEVELUPmats

/gbank sync
Broadcast cached bank snapshots to guild members who also have the addon.

/gbank request
Ask online officers/bankers with the addon to sync their latest snapshot.

/gbank limit Item Name = 80
Track minimum stock for an item. Example:
/gbank limit Greater Fire Protection Potion = 80

/gbank stock
Print low-stock items to your chat window.

/gbank clear
Clear local cached bank data.

Recommended officer workflow
----------------------------
1. Log into the bank alt.
2. Open bags, bank, and mailbox.
3. Run /gbank scan LEVELUPraid
4. Run /gbank sync

Recommended member workflow
---------------------------
1. Install addon.
2. Run /gbank request, or wait for officer sync.
3. Run /gbank and search.

Notes
-----
This addon uses old Vanilla addon messages through SendAddonMessage.
It is intentionally simple and avoids modern Classic APIs.


0.2.1: Changed addon sync delimiter from | to ~ because Vanilla chat treats | as an escape character and can throw Invalid escape code in chat message.
