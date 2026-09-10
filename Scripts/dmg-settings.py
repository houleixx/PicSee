"""Finder layout embedded by dmgbuild, without a running Finder or AppleScript.

Settings reference: https://dmgbuild.readthedocs.io/en/latest/settings.html
"""

import os.path
import subprocess

application = defines["app"]
background = defines["background"]

format = "UDZO"
filesystem = "HFS+"
files = [application]
symlinks = {"Applications": "/Applications"}
# Do not set FinderInfo on the signed app to hide its extension: codesign
# rejects that metadata when the downloaded image is verified by Gatekeeper.
hide_extensions = []

# Finder includes its title/status chrome in WindowBounds; leave enough height
# for the 340 point background so the installation instruction is never clipped.
window_rect = ((240, 180), (560, 390))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
include_list_view_settings = False

arrange_by = None
icon_locations = {"PicSee.app": (150, 164), "Applications": (410, 164)}
icon_size = 80
text_size = 13
label_pos = "bottom"
show_icon_preview = False
grid_offset = (0, 0)
scroll_position = (0, 0)


def create_hook(mount_point, options):
    """Reject packaging metadata that invalidates the copied app's signature."""
    subprocess.run(
        ["/usr/bin/codesign", "--verify", "--deep", "--strict",
         os.path.join(mount_point, "PicSee.app")],
        check=True,
    )
