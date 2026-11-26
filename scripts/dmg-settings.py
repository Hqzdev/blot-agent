"""Finder settings for the Ori macOS installer."""
from pathlib import Path

application = defines['app']
app_name = Path(application).name
format = 'UDZO'
filesystem = 'HFS+'
files = [application]
symlinks = {'Applications': '/Applications'}
hide_extension = [app_name]
background = defines['background']
window_rect = ((200, 200), (760, 500))
default_view = 'icon-view'
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
include_icon_view_settings = True
arrange_by = None
icon_size = 144
text_size = 16
label_pos = 'bottom'
icon_locations = {app_name: (220, 154), 'Applications': (540, 154)}
