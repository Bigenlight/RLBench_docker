# VLA Evaluation on RLBench — Docker Overlays

This directory holds **per-VLA Docker overlays** that run individual
Vision-Language-Action models against the headless RLBench setup in this repo.
Each subfolder is a self-contained Dockerfile + entrypoint + patches + README
+ example outputs for one VLA.

## Currently supported

| VLA | Folder | Backbone | Repo |
|---|---|---|---|
| BridgeVLA (NeurIPS 2025) | [`bridgevla/`](./bridgevla/) | PaliGemma-3B (3D, MVT) | https://github.com/BridgeVLA/BridgeVLA |
| TGM-VLA | [`tgm_vla/`](./tgm_vla/) | SAM2-Hiera-B+ + MVT 2-stage + CLIP RN50 | https://github.com/PuFanqi23/TGM-VLA |

> Adding a VLA? See [Adding a new VLA](#adding-a-new-vla) below.

---

## Quick start — pick a VLA and follow its README

Each VLA folder is independent. To eval one:

```bash
cd RLBench_docker
docker build -t <vla>:latest \
    --build-arg ACCEPT_<VLA>_LICENCE=YES \
    -f vla/<vla>/Dockerfile .
# Then follow vla/<vla>/README.md for checkpoint download + run commands.
```

For BridgeVLA specifically: [`bridgevla/README.md`](./bridgevla/README.md).

---

## Why each VLA gets its own self-contained image

The base `docker/Dockerfile` (default RLBench dev image) is **not** a useful
parent for most VLAs because:

- Python pin differs (base = 3.8; BridgeVLA = 3.9; future VLAs may need 3.10/3.11).
- RLBench fork differs (base = `stepjam/RLBench` HEAD; BridgeVLA =
  `buttomnutstoast/RLBench@587a6a0e6`; PerAct/RVT family pin yet other commits).
- Torch/CUDA combos diverge wildly between VLAs and the cost of keeping a
  single "fat base" that satisfies all of them is higher than the cost of
  ~10 minutes of layer cache misses per VLA build.

So each VLA folder owns its full Dockerfile, *from CUDA base up*, and shares
only the **patterns** documented below — not literal image layers.

---

## The shared pattern (copy into each new VLA Dockerfile)

These three blocks are responsible for headless RLBench actually working,
and every VLA Dockerfile must include them verbatim (or equivalent). See
[`docker/README.md`](../docker/README.md) for the full root-cause writeup
of why each one is needed.

### 1. CoppeliaSim 4.1.0 Edu install (newer = PyRep segfault)

```dockerfile
ENV COPPELIASIM_ROOT=/opt/coppeliasim
RUN mkdir -p ${COPPELIASIM_ROOT} && \
    wget -qO /tmp/cs.tar.xz \
        https://downloads.coppeliarobotics.com/V4_1_0/CoppeliaSim_Edu_V4_1_0_Ubuntu20_04.tar.xz && \
    tar -xf /tmp/cs.tar.xz -C ${COPPELIASIM_ROOT} --strip-components=1 && \
    rm /tmp/cs.tar.xz
```

### 2. Qt plugin discovery — the one line that makes vision sensors not all-zero

```dockerfile
ENV LD_LIBRARY_PATH=${COPPELIASIM_ROOT}:${LD_LIBRARY_PATH} \
    QT_QPA_PLATFORM_PLUGIN_PATH=${COPPELIASIM_ROOT}/platforms \
    QT_PLUGIN_PATH=${COPPELIASIM_ROOT}
```

The third line — `QT_PLUGIN_PATH=${COPPELIASIM_ROOT}` — is the non-obvious
one. Without it, CoppeliaSim's bundled Qt5 cannot find its
`xcbglintegrations/` directory under Xvfb and vision sensors silently
return all-zero frames. The fix is the same one used by the base image.

### 3. Xvfb-on-demand entrypoint (start `:99` if `$DISPLAY` unset)

Each VLA folder ships its own `entrypoint.sh` with this preamble — see
[`bridgevla/entrypoint.sh`](./bridgevla/entrypoint.sh) for the canonical
version. Per-VLA logic (e.g. installing vendored bind-mounted libs on
first run) goes after the Xvfb block.

The Dockerfile glues it in:

```dockerfile
COPY vla/<name>/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["tini", "-g", "--", "/entrypoint.sh"]
CMD ["bash"]
```

### 4. License gate (each VLA has its own clause set)

```dockerfile
ARG ACCEPT_<VLA>_LICENCE=
RUN if [ "$ACCEPT_<VLA>_LICENCE" != "YES" ]; then \
        echo "Building this image requires accepting: RLBench, CoppeliaSim Edu, <VLA>"; \
        exit 1; \
    fi
```

---

## Adding a new VLA

Concretely, when adding `vla/<name>/`:

1. **Create the folder layout:**
   ```
   vla/<name>/
   ├── Dockerfile              # FROM nvidia/cuda:... + the 4 shared blocks above + <name>-specific deps
   ├── entrypoint.sh           # Xvfb preamble + any bind-mount lib install
   ├── patches/                # *.patch files to apply to the upstream <name> repo
   ├── examples/               # eval result mp4s for the README to link to
   └── README.md               # TL;DR build / patch / checkpoint / run / known limitations
   ```

2. **Update `.dockerignore`** at the repo root: add a `!vla/<name>/entrypoint.sh`
   exemption so the build context can see the entrypoint.

3. **Update this README's "Currently supported" table** with the new entry.

4. **Update the top-level [`README.md`](../README.md)** if the VLA is a
   headline addition.

5. **Test the build end-to-end** before committing:
   ```bash
   docker build -t <name>:latest \
       --build-arg ACCEPT_<VLA>_LICENCE=YES \
       -f vla/<name>/Dockerfile .
   # then run a 1-episode eval per the VLA's README and confirm a video appears.
   ```

### Patch hygiene

Patches under `vla/<name>/patches/` should target the upstream `<name>` repo
(bind-mounted at container runtime, not COPYed in), be **idempotent under
`patch -p1 --forward`**, and include a top-of-file comment explaining the
*why* — not just the diff. See `vla/bridgevla/patches/*.patch` for examples.

### License posture (important)

All current VLAs in this directory bundle non-redistribution licenses
(RLBench academic-only, CoppeliaSim Edu academic-only, plus the VLA's own
clauses). **Do NOT push images built from these Dockerfiles to public
registries.** Builds happen locally per-user, gated by `--build-arg
ACCEPT_<VLA>_LICENCE=YES`.
