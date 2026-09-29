import os
import sys
import pya

base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
gds_path = os.path.join(base_dir, "openlane", "runs", "tc_poster_run", "final", "gds", "npu_top.gds")
pdk_root = os.environ.get("PDK_ROOT", "/root/.volare/volare/sky130/versions/0fe599b2afb6708d281543108caf8310912f54af")
lyp_path = os.path.join(pdk_root, "sky130A", "libs.tech", "klayout", "tech", "sky130A.lyp")
out_dir = os.path.join(base_dir, "docs", "figures")
os.makedirs(out_dir, exist_ok=True)

out_macro = os.path.join(out_dir, "npu_top_macro_layout.png")
out_zoom = os.path.join(out_dir, "npu_top_core_zoom.png")

print(f"Loading {gds_path} in KLayout...")
app = pya.Application.instance()
mw = app.main_window()
mw.load_layout(gds_path, 0)
view = mw.current_view()

print(f"Applying SkyWater 130 layer properties: {lyp_path}")
view.load_layer_props(lyp_path)
view.max_hier()
view.zoom_fit()

print(f"Saving high-res macro image: {out_macro}")
view.save_image(out_macro, 3840, 2160)

# Zoom into central systolic array
cell = view.active_cellview().cell
bbox = cell.bbox()
cx = (bbox.left + bbox.right) // 2
cy = (bbox.bottom + bbox.top) // 2
sx = (bbox.right - bbox.left) // 4
sy = (bbox.top - bbox.bottom) // 4
zoom_box = pya.DBox((cx - sx) * 0.001, (cy - sy) * 0.001, (cx + sx) * 0.001, (cy + sy) * 0.001)
view.zoom_box(zoom_box)

print(f"Saving zoomed-in core image: {out_zoom}")
view.save_image(out_zoom, 3840, 2160)

print("KLayout export complete successfully!")
app.exit(0)
