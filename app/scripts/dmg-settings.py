# Layout of the disk image, read by dmgbuild (see make-dmg.sh): a quiet window with the app on the left, a shortcut
# to Applications on the right, and the picture from DmgBackgroundArt (Theme.swift) behind them.
import os

app = defines["app"]  # noqa: F821  (dmgbuild provides `defines`)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = defines["icon"]  # noqa: F821  the volume's own icon
background = defines["bg"]  # noqa: F821

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
arrange_by = None

# The artwork is 660 x 400; Finder's title bar takes about 28 pt of the window, so the window is that much taller.
window_rect = ((200, 120), (660, 428))
icon_size = 128
text_size = 13
icon_locations = {os.path.basename(app): (180, 190), "Applications": (480, 190)}
