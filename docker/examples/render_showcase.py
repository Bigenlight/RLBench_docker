"""RLBench task showcase — render a representative subset of tasks to PNG.

Renders three groups of scenes to `/output/renders/` (mount a host volume to
that path in the container to get the PNGs out):

    peract18/    — 18 PerAct-protocol tasks (the de-facto VLA standard) at variation 0
    other/       — 10 visually diverse tasks beyond PerAct-18
    multiview/   — 3 tasks × 4 cameras (front, wrist, left_shoulder, right_shoulder)
                   at 384×384, demonstrating what a multi-view VLA "sees"

Usage (from the host):

    mkdir -p ~/rlbench-renders
    docker run --rm --gpus all -e NVIDIA_DRIVER_CAPABILITIES=all \\
        -v ~/rlbench-renders:/output \\
        -v $PWD/docker/examples:/examples:ro \\
        rlbench:latest python /examples/render_showcase.py

Expected output: ~40 PNGs, each ~70-100 KB (real renders). If files are
~270 bytes each, rendering is silently producing all-zero frames — see
docker/README.md §"Why QT_PLUGIN_PATH" for the root cause and fix.
"""

import os
import time

from PIL import Image
from rlbench import utils as rlb_utils
from rlbench.action_modes.action_mode import MoveArmThenGripper
from rlbench.action_modes.arm_action_modes import JointVelocity
from rlbench.action_modes.gripper_action_modes import Discrete
from rlbench.environment import Environment
from rlbench.observation_config import CameraConfig, ObservationConfig


PERACT_18 = [
    "close_jar", "reach_and_drag", "insert_onto_square_peg", "meat_off_grill",
    "open_drawer", "place_cups", "stack_wine", "push_buttons",
    "put_groceries_in_cupboard", "put_item_in_drawer", "put_money_in_safe",
    "light_bulb_in", "slide_block_to_target", "place_shape_in_shape_sorter",
    "stack_blocks", "stack_cups", "sweep_to_dustpan", "turn_tap",
]

OTHER_TASKS = [
    "set_the_table", "solve_puzzle", "scoop_with_spatula", "water_plants",
    "basketball_in_hoop", "toilet_seat_down", "play_jenga", "open_microwave",
    "empty_dishwasher", "pour_from_cup_to_cup",
]

MULTIVIEW_TASKS = ["stack_blocks", "put_item_in_drawer", "turn_tap"]

OUTPUT_ROOT = "/output/renders"


def _make_obs_cfg(image_size=(256, 256), front=True, wrist=False, shoulders=False):
    cam_on = CameraConfig(
        rgb=True, depth=False, point_cloud=False, mask=False,
        image_size=image_size,
    )
    cam_off = CameraConfig()
    cam_off.set_all(False)
    return ObservationConfig(
        front_camera=cam_on if front else cam_off,
        wrist_camera=cam_on if wrist else cam_off,
        left_shoulder_camera=cam_on if shoulders else cam_off,
        right_shoulder_camera=cam_on if shoulders else cam_off,
        overhead_camera=cam_off,
    )


def _new_env(obs_cfg):
    return Environment(
        action_mode=MoveArmThenGripper(JointVelocity(), Discrete()),
        obs_config=obs_cfg,
        headless=True,
    )


def render_single(env, task_name, var_idx, out_dir):
    """Render one (task, variation) and save the front-camera frame."""
    try:
        task_cls = rlb_utils.name_to_task_class(task_name)
    except Exception as e:
        return f"ERR (resolve): {e}", -1
    try:
        te = env.get_task(task_cls)
        if var_idx >= te.variation_count():
            return f"SKIP (var{var_idx} >= count {te.variation_count()})", -1
        te.set_variation(var_idx)
        descs, obs = te.reset()
    except Exception as e:
        return f"ERR (reset): {e}", -1

    out = f"{out_dir}/{task_name}_var{var_idx:02d}.png"
    Image.fromarray(obs.front_rgb).save(out)
    return descs[0], int(obs.front_rgb.max())


def render_multiview(env, task_name, out_dir):
    """Render one task at variation 0 from 4 cameras."""
    task_cls = rlb_utils.name_to_task_class(task_name)
    te = env.get_task(task_cls)
    te.set_variation(0)
    descs, obs = te.reset()
    for cam_name, rgb in [
        ("front", obs.front_rgb),
        ("wrist", obs.wrist_rgb),
        ("left_shoulder", obs.left_shoulder_rgb),
        ("right_shoulder", obs.right_shoulder_rgb),
    ]:
        Image.fromarray(rgb).save(f"{out_dir}/{task_name}_{cam_name}.png")
    return descs[0]


def main():
    os.makedirs(f"{OUTPUT_ROOT}/peract18", exist_ok=True)
    os.makedirs(f"{OUTPUT_ROOT}/other", exist_ok=True)
    os.makedirs(f"{OUTPUT_ROOT}/multiview", exist_ok=True)

    # --- single front camera @ 256² for PerAct-18 + other ---
    env = _new_env(_make_obs_cfg(image_size=(256, 256), front=True))
    t0 = time.time()
    env.launch()
    print(f"env.launch(): {time.time() - t0:.1f}s\n", flush=True)

    print("=== PerAct-18 subset (front, var0) ===")
    for t in PERACT_18:
        lang, mx = render_single(env, t, 0, f"{OUTPUT_ROOT}/peract18")
        marker = "✓" if mx > 0 else "✗"
        print(f"  {marker} {t:35s} {lang!r}")

    print("\n=== Diverse other tasks ===")
    for t in OTHER_TASKS:
        lang, mx = render_single(env, t, 0, f"{OUTPUT_ROOT}/other")
        marker = "✓" if mx > 0 else "✗"
        print(f"  {marker} {t:35s} {lang!r}")

    env.shutdown()

    # --- 4-view multi-camera @ 384² ---
    print("\n=== Multi-camera (4 views @ 384²) ===")
    env2 = _new_env(_make_obs_cfg(
        image_size=(384, 384), front=True, wrist=True, shoulders=True,
    ))
    env2.launch()
    for t in MULTIVIEW_TASKS:
        lang = render_multiview(env2, t, f"{OUTPUT_ROOT}/multiview")
        print(f"  ✓ {t:25s} {lang!r}  (4 cameras saved)")
    env2.shutdown()

    print("\nDONE — outputs at", OUTPUT_ROOT)


if __name__ == "__main__":
    main()
