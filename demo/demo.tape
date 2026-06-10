# Regenerate demo/demo.gif with charmbracelet/vhs:
#
#   ./demo/setup.sh            # build the scratch repo at /tmp/demo-augur
#   vhs demo/demo.tape         # render demo.gif, then move it into site/public
#
# Requires `augur` and `vhs` on PATH (brew install corvidlabs/tap/augur charmbracelet/tap/vhs).
Output demo.gif
Set FontSize 20
Set Width 1200
Set Height 600
Set Padding 30
Set Theme "Catppuccin Mocha"
Set TypingSpeed 40ms
Hide
Type "cd /tmp/demo-augur && clear"
Enter
Show
Sleep 500ms
Type "# augur: is this change safe, or should a human look?"
Sleep 700ms
Enter
Sleep 300ms
Type "augur check"
Sleep 500ms
Enter
Sleep 5s
