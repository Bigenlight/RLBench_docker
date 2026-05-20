# RLBench Docker — Standalone Headless Setup

Minimal, self-contained Dockerfile to run [RLBench](https://github.com/stepjam/RLBench)
+ PyRep + CoppeliaSim 4.1.0 **headlessly** in Docker on a Linux host with an
NVIDIA GPU, with **real camera rendering** (not the silent all-zero / black
frame failure mode that most setups online run into).

The whole thing is ~110 lines of Dockerfile + 25 lines of entrypoint. The
secret is one environment variable that's missing from every guide we found.

---

## TL;DR

```bash
# Build (from this repo's root, with license acceptance)
docker build -t rlbench:latest \
    --build-arg ACCEPT_RLBENCH_LICENCE=YES \
    -f docker/Dockerfile .

# Interactive shell
docker run --rm -it --gpus all rlbench:latest

# Inside the container:
python -c "
from rlbench.environment import Environment
from rlbench.action_modes.action_mode import MoveArmThenGripper
from rlbench.action_modes.arm_action_modes import JointVelocity
from rlbench.action_modes.gripper_action_modes import Discrete
from rlbench.observation_config import CameraConfig, ObservationConfig
from rlbench import utils as rlb_utils

cam = CameraConfig(rgb=True, depth=False, point_cloud=False, mask=False, image_size=(256, 256))
cam_off = CameraConfig(); cam_off.set_all(False)
obs_cfg = ObservationConfig(front_camera=cam, wrist_camera=cam_off,
                             left_shoulder_camera=cam_off, right_shoulder_camera=cam_off,
                             overhead_camera=cam_off)
env = Environment(action_mode=MoveArmThenGripper(JointVelocity(), Discrete()),
                  obs_config=obs_cfg, headless=True)
env.launch()
te = env.get_task(rlb_utils.name_to_task_class('reach_target'))
te.set_variation(0)
descs, obs = te.reset()
print(descs[0], '|', 'max RGB =', obs.front_rgb.max())
env.shutdown()
"
# → 'reach the red target' | max RGB = 254
```

A non-zero max RGB on first try means rendering is working. See
[`examples/render_showcase.py`](./examples/render_showcase.py) for a fuller
demo that produces ~40 task scene PNGs across the PerAct-18 subset and
diverse other tasks.

---

## What's inside

| Layer | Version |
|---|---|
| Base image | `nvidia/cuda:12.1.1-runtime-ubuntu22.04` (Ubuntu 22.04, glibc 2.35) |
| Python | 3.8 from deadsnakes PPA (PyRep ctypes binding requires this exactly) |
| CoppeliaSim | **4.1.0 Edu** Ubuntu20.04 build (PyRep/RLBench pin this; newer = segfault) |
| PyRep | HEAD of `stepjam/PyRep` (commit-pinnable via `--build-arg PYREP_REF=<sha>`) |
| RLBench | THIS repo (via `COPY . /opt/RLBench`) — fork content is what ends up in the image |
| Headless display | `Xvfb :99` on demand from entrypoint (skipped if `$DISPLAY` set) |
| GPU rendering path | Xvfb's software GLX → CoppeliaSim's OpenGL3 plugin (works because `QT_PLUGIN_PATH` is set, see below) |
| Optional GPU acceleration | VirtualGL 3.1.2 (installed but not required for the standard path) |
| Init / signal handling | `tini` PID 1 (reaps CoppeliaSim child processes cleanly) |

Final image is ~6.6 GB (most of it CUDA + Python + CoppeliaSim binaries).

---

## Why `QT_PLUGIN_PATH` — the root cause writeup

This is the discovery that turns this image from "shape-correct but all-black
frames" (where most online setups land) into "actually renders". If you've ever
fought with CoppeliaSim + Docker + headless and given up because the camera
output is mysteriously zero, this is for you.

### The symptom

```python
descs, obs = task_env.reset()
print(obs.front_rgb.shape)   # (256, 256, 3) ✅
print(obs.front_rgb.max())   # 0            ✗ silent failure
```

No exception, correct shape, every pixel is `(0, 0, 0)`. `sim.simHandleVisionSensor`
returns `0` (success). `sim.simGetVisionSensorImage` returns a zero-initialized
buffer. PyRep wraps it with NumPy and life proceeds.

### Common (wrong) diagnoses

- "Xvfb's software GLX can't do OpenGL"
- "Need VirtualGL"
- "Need a real GPU-backed X server (`nvidia-xconfig` + `sudo X :99`)"
- "Need `QT_QPA_PLATFORM=offscreen`"
- "Need `QT_QPA_PLATFORM=eglfs` or `minimalegl`"
- "The `libsimExtOpenGL3Renderer.so` plugin needs to be disabled"

We tried all of these. Some failed loudly (Qt eglfs needs a non-shipped
`libQt5EglFSDeviceIntegration.so.5`; offscreen "does not support
createPlatformOpenGLContext"; vglrun's LD_PRELOAD doesn't intercept Qt's
internal GLX queries). Others failed silently and produced the same all-zero
output.

### The actual cause

Qt's xcb platform plugin (`libqxcb.so`) needs to create an OpenGL context when
the application asks for one. To do that, it loads a **GL-integration
sub-plugin** from a directory called `xcbglintegrations/` — specifically
`libqxcb-glx-integration.so` for the GLX backend.

CoppeliaSim 4.1.0 ships this directory at:
```
/opt/coppeliasim/xcbglintegrations/
```

But guides typically set:
```
QT_QPA_PLATFORM_PLUGIN_PATH=/opt/coppeliasim/platforms      # where libqxcb.so lives
```

Qt looks for `xcbglintegrations/` as a sibling of wherever it loaded the xcb
plugin from. With the above, it looks at `/opt/coppeliasim/platforms/xcbglintegrations/`
— which doesn't exist. Qt prints:
```
QXcbIntegration: Cannot create platform OpenGL context, neither GLX nor EGL are enabled
```
and gives up. CoppeliaSim then either segfaults (when it tries to use the
context anyway) or — if the plugin happens to be disabled — silently returns
zero-filled frames.

### The fix

```dockerfile
ENV QT_PLUGIN_PATH=${COPPELIASIM_ROOT}
```

One line. `QT_PLUGIN_PATH` is an additional Qt plugin search path that the
xcb plugin uses to find its sub-plugin directories. With it pointing at
`COPPELIASIM_ROOT`, Qt finds `xcbglintegrations/` as a direct subdirectory,
loads `libqxcb-glx-integration.so`, and successfully creates a GLX context
over Xvfb's software framebuffer.

After this:

- `RenderMode.OPENGL` (built-in renderer): renders real frames.
- `RenderMode.OPENGL3` (the high-quality plugin renderer, default in
  `CameraConfig`): also renders real frames.
- No VirtualGL needed.
- No host X11 socket mounting needed.
- No `nvidia-xconfig` / `sudo X :99` needed.
- Plugin (`libsimExtOpenGL3Renderer.so`) does **NOT** need to be disabled.

### Why this isn't more widely documented

Most RLBench / CoppeliaSim Docker recipes online either:
- Use a host-mounted real X server (and never hit the issue because that X server provides GLX through nvidia's libGLX),
- Or they disable the OpenGL3 plugin to "avoid the Xvfb segfault" and don't notice their frames are all zero (e.g. their CI only checks shape, not pixel content).

Hybrid-VLA's [`test.sh`](https://github.com/PKU-HMI-Lab/Hybrid-VLA/blob/main/test.sh)
incidentally works because it uses `QT_QPA_PLATFORM_PLUGIN_PATH=$COPPELIASIM_ROOT`
(without the `/platforms` suffix) — that ALSO causes Qt to find
`xcbglintegrations/` as a sibling. They got the right behavior for an unstated
reason; their `_PLUGIN_PATH` "in the wrong place" was actually keeping things
working.

---

## Examples

[`examples/render_showcase.py`](./examples/render_showcase.py) renders
all 18 PerAct-protocol tasks at variation 0, 10 visually diverse other
tasks, and a 4-camera multi-view set, saving ~40 PNGs to `/output/renders/`.

```bash
mkdir -p ~/rlbench-renders
docker run --rm --gpus all -e NVIDIA_DRIVER_CAPABILITIES=all \
    -v ~/rlbench-renders:/output \
    -v $PWD/docker/examples:/examples:ro \
    rlbench:latest python /examples/render_showcase.py
ls ~/rlbench-renders/renders/peract18/
```

Output structure:
```
~/rlbench-renders/renders/
├── peract18/    18 frames — close_jar, stack_blocks, ... (PerAct VLA standard)
├── other/       10 frames — set_the_table, play_jenga, ... (visually diverse)
└── multiview/   12 frames — 3 tasks × 4 cameras (front, wrist, L-shoulder, R-shoulder) @ 384²
```

---

## Reproducibility

PyRep is cloned from upstream HEAD by default. Pin to a specific commit:
```bash
docker build -t rlbench:pinned \
    --build-arg ACCEPT_RLBENCH_LICENCE=YES \
    --build-arg PYREP_REF=<sha> \
    -f docker/Dockerfile .
```

RLBench is taken from this repo's working tree (`COPY . /opt/RLBench`), so
the image is naturally pinned to the repo's HEAD at build time. Tag this
repo (`git tag rlbench-docker-v1.0`) before building if you want a stable
reference.

---

## Notes on the host

- Tested on Ubuntu 24.04.4 host (kernel 6.17, glibc 2.39) with NVIDIA RTX 3060
  + driver 590.x + Docker 29.2.1 + NVIDIA Container Toolkit 1.18.2.
- Container is Ubuntu 22.04 (glibc 2.35) — CoppeliaSim 4.1.0 Ubuntu20.04
  binaries work on 22.04 because CoppeliaSim bundles its own Qt5 + libs.
- The host can be Wayland — the container uses its own Xvfb on `:99`, no host
  X11 is touched.

---

## License

This Docker setup is layered on top of two non-redistribution licenses:

1. **RLBench** — Imperial College London, academic / non-commercial.
   [LICENSE in this repo's root](../LICENSE).
2. **CoppeliaSim Edu** — Coppelia Robotics AG, educational / non-commercial.
   [coppeliarobotics.com/licensing](https://manual.coppeliarobotics.com/en/licensing.htm).

The Dockerfile gates the build behind `ACCEPT_RLBENCH_LICENCE=YES` to make
the license acceptance explicit. **Do NOT push images built from this Dockerfile
to a public registry** — both bundled components forbid redistribution.

---

## Acknowledgements

- [stepjam/RLBench](https://github.com/stepjam/RLBench) — the underlying benchmark.
- [stepjam/PyRep](https://github.com/stepjam/PyRep) — Python bindings for CoppeliaSim.
- [PKU-HMI-Lab/Hybrid-VLA](https://github.com/PKU-HMI-Lab/Hybrid-VLA) — whose
  `test.sh` provided the critical hint about the `QT_QPA_PLATFORM_PLUGIN_PATH`
  vs `xcbglintegrations` discovery.
- The `QT_PLUGIN_PATH` root-cause writeup above was assembled via a multi-agent
  investigation on 2026-05-20 after several days of misdiagnoses.
