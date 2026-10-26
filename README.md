# ClipboardBar

A small menu bar clipboard history app for macOS 13+ (Apple Silicon or Intel).

## Install

1. Unzip this folder (e.g. in Downloads).
2. Open **Terminal**, then run:

       cd ~/Downloads/ClipboardBar
       bash build.sh

   If macOS asks to install Command Line Tools, click Install, wait, then run the command again.
3. A clipboard icon appears in the menu bar. The app is now in /Applications.

## Use

- Click the menu bar icon (or press **Control + Option + V**) to open the popup.
- Click any item and it is pasted straight into the field you were typing in.
  First time, macOS asks for Accessibility permission: System Settings > Privacy & Security >
  Accessibility > switch ClipboardBar on. Without it, the item is only copied (press Cmd+V yourself).
  After rebuilding, if pasting stops working, remove ClipboardBar from that list with the - button and add it again.
- Pin icon keeps an item at the top and safe from "Clear unpinned".
- X deletes one item. Trash menu clears unpinned or everything.
- Pause button stops recording. Gear menu: launch at login, quit.
- Esc or clicking elsewhere closes the popup.

## Notes

- Text only. Up to 200 unpinned items kept.
- History is stored as plain text in ~/Library/Application Support/ClipboardBar/history.json.
- Items marked secret by password managers are skipped.
- To uninstall: quit from the gear menu, delete /Applications/ClipboardBar.app and the folder above.
