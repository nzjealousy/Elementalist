"""Rebuilds every generated picture in the Moonlit Glyphwork style, then runs the art gate.
Run: python tools/art/build_all.py            (about a minute; stdlib only)

Order: runes (UI icons) -> vfx -> ui frames -> tiles -> hero parts -> monsters and props -> check_art.
"""
import os
import runpy
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

for script in ('gen_runes.py', 'gen_vfx.py', 'gen_ui.py', 'gen_tiles.py', 'gen_heroes.py', 'gen_sprites.py', 'gen_portal.py', 'gen_items.py'):
    print('==', script)
    runpy.run_path(os.path.join(HERE, script), run_name='__main__')
print('== check_art.py')
runpy.run_path(os.path.join(HERE, 'check_art.py'), run_name='__main__')
