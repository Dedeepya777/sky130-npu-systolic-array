#!/usr/bin/env python3
"""
Silicon Layout Image Renderer using KLayout Python API (pya)
Renders high-resolution publication-quality PNG layout images for the TechConnect poster.
"""

import os
import sys
import pya

def render_gds(gds_path, lyp_path, out_full_png, out_zoom_png=None, width=3840, height=2160):
    if not os.path.exists(gds_path):
        print(f"Error: GDS file not found: {gds_path}")
        return False

    print(f"Loading GDSII stream: {gds_path}")
    app = pya.Application.instance()
    mw = pya.MainWindow.instance()
    if mw is None:
        # Running in off-screen / batch mode
        mw = pya.MainWindow()

    view = mw.create_layout(0)
    layout = view.cellview(0).layout()
    layout.read(gds_path)

    # Load SkyWater 130 layer properties if provided
    if lyp_path and os.path.exists(lyp_path):
        print(f"Applying Sky130 layer properties: {lyp_path}")
        view.load_layer_props(lyp_path)

    view.max_hier()
    view.zoom_fit()

    os.makedirs(os.path.dirname(os.path.abspath(out_full_png)), exist_ok=True)
    print(f"Exporting full macro render ({width}x{height}) -> {out_full_png}")
    view.save_image(out_full_png, width, height)

    if out_zoom_png:
        # Calculate bounding box of core cell
        top_cell = layout.top_cell()
        bbox = top_cell.bbox()
        # Zoom to central 50%
        center_x = (bbox.left + bbox.right) // 2
        center_y = (bbox.bottom + bbox.top) // 2
        span_x = (bbox.right - bbox.left) // 4
        span_y = (bbox.top - bbox.bottom) // 4
        zoom_box = pya.DBox(
            (center_x - span_x) * layout.dbu,
            (center_y - span_y) * layout.dbu,
            (center_x + span_x) * layout.dbu,
            (center_y + span_y) * layout.dbu,
        )
        view.zoom_box(zoom_box)
        print(f"Exporting systolic core zoom render ({width}x{height}) -> {out_zoom_png}")
        view.save_image(out_zoom_png, width, height)

    print("Layout rendering complete!")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Usage: python3 render_layout.py <gds_path> <lyp_path> <out_full_png> [out_zoom_png]")
        sys.exit(1)

    gds = sys.argv[1]
    lyp = sys.argv[2]
    out_full = sys.argv[3]
    out_zoom = sys.argv[4] if len(sys.argv) > 4 else None

    render_gds(gds, lyp, out_full, out_zoom)
