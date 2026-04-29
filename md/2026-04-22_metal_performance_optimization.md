# Metal 渲染性能优化记录（2026-04-22）

本文记录本轮对 `MetalCMakeDemo` 的性能检查结论、已落地优化、背后的 Metal 经验，以及后续可继续推进的方向。

## 本轮优化目标

当前项目是教学型 Metal Demo，优先保证 15 个主题都能稳定切换、可观察、可解释。本轮优化不改变整体教学结构，主要处理几个“收益明确、风险较低”的性能点：

- 减少不必要的 MSAA 带宽和 resolve。
- 降低全屏 compute pass 的无效执行。
- 降低粒子主题的全屏像素计算压力。
- 减少 Bloom 多 encoder 带来的 CPU 编码开销。
- 让 shader 在效果关闭时少采样无关纹理。

## 已落地优化

### 1. Post Pass 去掉 MSAA

优化前：

- Scene Pass 使用 MSAA x4。
- Post Pass 也使用 `_postMSAATexture` 做 MSAA x4。
- Post Pass 最后再 resolve 到 `drawable.texture`。

问题：

- Post Pass 只画一个全屏三角形，不存在几何边缘需要抗锯齿。
- Scene Pass 已经完成 MSAA resolve。
- Post Pass 再做 MSAA 会额外消耗显存、带宽和 resolve 成本。

优化后：

- 删除 `_postMSAATexture`。
- `_postPipelineState` 使用默认 sampleCount 1。
- Post Pass 直接写入 `drawable.texture`。
- `storeAction` 从 `MTLStoreActionMultisampleResolve` 改为 `MTLStoreActionStore`。

经验：

> 后处理 pass 通常不应该再开 MSAA。全屏后处理主要是采样和合成，目标是减少带宽，而不是重复做多重采样。

### 2. Edge Compute 按需执行

优化前：

- 除 deferred-like 主题外，每帧都会执行一次全分辨率 Sobel edge detect。
- `edge_detect_kernel` 每个像素读取 3x3 共 9 个邻域采样，窗口越大成本越高。
- 主题 9 中 `edgeStrength` 只有 `0.02`，视觉贡献很弱，但仍然执行整张图的 edge compute。

优化后：

- 增加 `useEdgeCompute = edgeStrength > 0.05f`。
- 当边缘强度低于阈值时跳过 edge compute，并把 `edgeStrength` 归零。
- Edge 关闭时不再创建空的 compute encoder。
- `post_fragment` 中也改为只有 `edgeStrength > 0.0001` 时才采样 `edgeTexture`。

经验：

> 屏幕空间 compute pass 应该有明确启用条件。即使视觉参数很小，全分辨率 kernel 的成本仍然是真实存在的。

### 3. 粒子纹理改为半分辨率

优化前：

- `_particleTexture` 是 full-res `RGBA16Float`。
- `particle_overlay_kernel` 对每个像素循环 48 个粒子中心。
- 成本接近 `width * height * 48`。

优化后：

- `_particleTexture` 改为 half-res。
- Post Pass 继续用 sampler 采样粒子纹理并叠加到全分辨率画面。

经验：

> 视觉上偏柔和的屏幕空间效果通常适合半分辨率。粒子、Bloom、雾、热浪、体积光都可以优先尝试降分辨率。

### 4. Bloom compute encoder 合并

优化前：

- Bright extract、horizontal blur、vertical blur 分别创建一个 compute encoder。
- 每个 encoder 都有创建、设置、结束的 CPU 编码成本。

优化后：

- 合并为一个 `bloomEncoder`。
- 在同一个 compute encoder 中依次 dispatch bright extract、blur H、blur V。
- 在相邻读写阶段之间加入 `memoryBarrierWithScope:MTLBarrierScopeTextures`，明确保证纹理写入对后续 dispatch 可见。

经验：

> 多个连续 compute 阶段如果资源依赖简单，可以合并到一个 encoder，减少 CPU 编码开销。但同一 encoder 内前后 dispatch 有读写依赖时，应显式考虑 memory barrier。

### 5. Shader 侧减少无效采样

优化前：

- `post_fragment` 总是采样 `edgeTexture`，再乘以 `edgeStrength`。
- 即使边缘强度接近 0，也会发生纹理采样。

优化后：

- 使用条件表达式：

```metal
float edge = params.edgeStrength > 0.0001
           ? edgeTexture.sample(postSampler, in.uv).r * params.edgeStrength
           : 0.0;
```

经验：

> CPU 侧跳过 pass 之后，shader 侧也要同步跳过对应采样，否则可能读到旧纹理内容，也会浪费带宽。

## 当前仍保留的教学型开销

### 1. Parallel Encoder 示例粒度仍然很小

主题 5 仍然对一个 36-index 立方体拆成两个 sub-encoder。这个路径主要用于教学，真实性能收益不大，甚至可能因为 GCD 调度和同步而更慢。

后续工程化建议：

- 只有 draw call 数量足够多时才启用 parallel encoder。
- 或在 Demo 中明确标为“并行编码 API 展示路径”，不要把它当作小场景优化手段。

### 2. Post Pipeline 仍是单一通用版本

当前 `post_fragment` 仍声明 scene、edge、bloom、particle、history 五张纹理。虽然 shader 内已经对部分采样做条件控制，但最理想的性能路径是拆分多个 post pipeline：

- `post_base`
- `post_edge`
- `post_bloom`
- `post_particles`
- `post_temporal`
- `post_upscale`

后续工程化建议：

- 用 function constants 控制 post 功能开关。
- 或拆成多个 fragment function/pipeline。
- 各主题只绑定实际需要的纹理。

### 3. 中间纹理仍然按全主题预分配

当前项目为了运行时快速切换 15 个主题，会在 resize 时一次性准备 bloom、particle、history、half-res、upscaled 等纹理。

这对教学友好，但不是最省显存的做法。

后续工程化建议：

- 按主题懒创建资源。
- 或引入 transient texture pool。
- 更进一步可以用 `MTLHeap` 或 Render Graph 管理临时纹理生命周期。

## 优化前后渲染路径变化

优化前：

```text
Scene Pass (MSAA x4)
  -> sceneResolveTexture
  -> Edge Compute（大多数主题都跑）
  -> Bloom/Particles/Upscale（按主题）
  -> Post Pass (MSAA x4)
  -> resolve drawable
```

优化后：

```text
Scene Pass (MSAA x4)
  -> sceneResolveTexture
  -> Edge Compute（edgeStrength > 0.05 才跑）
  -> Bloom/Particles/Upscale（按主题，粒子半分辨率）
  -> Post Pass (sampleCount 1)
  -> drawable.texture
```

## 小白视角的性能经验总结

### 1. 先看“整屏跑了几遍”

全屏 pass 是 Metal 性能里最容易变贵的地方。一个 2560x1440 窗口约 368 万像素。一个全屏 compute 如果每像素读 9 次，就是三千多万次纹理读取。

所以要问：

- 这个 pass 是否每帧都必须跑？
- 能不能半分辨率？
- 能不能参数为 0 时跳过？
- 能不能和其他 pass 合并？

### 2. MSAA 不是哪里都要开

MSAA 适合有几何边缘的 scene pass。后处理 pass 通常是全屏三角形，不需要 MSAA。

判断方式：

- 画 3D 几何：可能需要 MSAA。
- 画 fullscreen triangle 做合成：通常不需要 MSAA。

### 3. 半分辨率是屏幕空间效果的常用武器

Bloom、粒子、雾、体积光、辉光等效果通常不需要 full-res。半分辨率能直接把像素数降到 1/4。

### 4. CPU 编码成本也要看

GPU pass 很贵时，优化 GPU。draw call 或 encoder 很多时，也要优化 CPU 编码。

本轮 Bloom encoder 合并就是减少 CPU 编码开销；Parallel Encoder 则提醒我们：多线程编码只有在任务足够大时才值得。

### 5. 跳过 pass 时，也要跳过 shader 采样

只在 CPU 侧不 dispatch 还不够。如果 shader 仍然采样旧纹理，可能会：

- 浪费带宽。
- 读到旧内容。
- 让后续调试变混乱。

## 本轮验证

已执行：

```bash
./script/build_and_run.sh --verify
```

结果：

- Xcode Debug build 成功。
- App 成功启动并通过运行检查。
