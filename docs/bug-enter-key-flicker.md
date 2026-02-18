# Bug 追踪：按回车键导致页面闪烁

## Bug 信息

- **Bug ID**: #001
- **严重程度**: 中等
- **状态**: 已确认
- **影响版本**: nvidia-egl-desktop-1.0.9 及更早版本
- **发现日期**: 2026-02-18
- **报告人**: 用户反馈

## 问题描述

在 Web 界面中按下回车键（Enter）时，页面会出现短暂的闪烁或冻结现象，表现为：

1. 视频流短暂中断（黑屏或冻结画面）
2. 音频流短暂中断
3. 页面可能显示"连接中"或"重新连接"提示
4. 持续时间约 0.5-2 秒

## 复现步骤

1. 启动容器并访问 Web 界面
2. 等待视频流连接建立完成
3. 在远程桌面中打开任意文本编辑器（如 Kate、KWrite）
4. 在文本编辑器中输入文字
5. 按下回车键（Enter）
6. 观察页面出现短暂闪烁或冻结

## 预期行为

按下回车键应该只在远程桌面中输入换行符，不应该影响 Web 界面的视频流播放。

## 实际行为

按下回车键会触发视频流和音频流的重新启动，导致短暂的中断和重连。

## 根本原因

### 代码分析

在 `addons/gstreamer-web/src/app.js` 中存在全局键盘事件监听器：

```javascript
// 第 172-174 行
mounted() {
  // 监听键盘事件
  window.addEventListener("keydown", this.handleKeyDown);
},

// 第 225-231 行
handleKeyDown(event) {
  // 检查是否按下 Enter 键
  if (event.key === "Enter") {
    console.log(`handleKeyDown: key Down: ${event.key}`);
    this.playStream();
  }
},

// 第 232-236 行
playStream() {
  webrtc.playStream();
  audio_webrtc.playStream();
  this.showStart = false;
}
```

### 问题分析

1. **全局监听**：`window.addEventListener` 监听整个页面的键盘事件，包括远程桌面内的输入
2. **无状态检查**：没有检查视频流是否已经在播放，任何时候按回车都会触发
3. **无条件重启**：`playStream()` 会无条件重新启动视频和音频流
4. **没有防抖**：快速按多次回车会导致多次重启流

### 设计意图

这个功能的原始设计意图是：

- 在连接建立后，如果浏览器的自动播放策略阻止了媒体播放
- 用户可以按回车键快速启动流媒体播放
- 避免需要点击"开启"按钮

但实现存在缺陷，没有考虑到流已经播放的情况。

## 影响范围

### 受影响的场景

- ✅ 在远程桌面的文本编辑器中输入文字
- ✅ 在远程桌面的终端中执行命令
- ✅ 在远程桌面的浏览器中填写表单
- ✅ 任何需要按回车键的操作

### 不受影响的场景

- ❌ 使用鼠标操作
- ❌ 按其他键盘按键（除了回车键）
- ❌ 使用虚拟键盘

## 修复方案

### 实现思路

原本有一个"开启"按钮，点击后会调用 `playStream()` 启动视频流，启动后按钮会隐藏（`showStart = false`）。

修复方案：将回车键与"开启"按钮绑定，只有在按钮显示时（流未启动）才响应回车键。一旦流已经启动，按钮隐藏，回车键就不再触发 `playStream()`。

### 代码修改

修改 `addons/gstreamer-web/src/app.js` 中的 `handleKeyDown` 方法：

```javascript
handleKeyDown(event) {
  // 只在显示"开启"按钮时响应回车键
  if (event.key === "Enter" && this.showStart === true && !event.repeat) {
    console.log(`handleKeyDown: Starting stream`);
    this.playStream();
  }
}
```

**关键逻辑**：

- `this.showStart === true`：只有在"开启"按钮显示时才响应（流未启动）
- `!event.repeat`：忽略长按重复事件，避免多次触发

### 修改说明

1. **第 227 行**：在 `if` 条件中添加 `this.showStart === true` 检查
2. **第 227 行**：添加 `!event.repeat` 防止长按重复触发

### 效果

- ✅ 流未启动时：按回车键 = 点击"开启"按钮，启动视频流
- ✅ 流已启动时：按回车键不会触发任何操作，正常输入到远程桌面
- ✅ 保留了原有的快捷启动功能
- ✅ 避免了误触发导致的闪烁问题

## 实施计划

### 短期（v1.0.10）

1. 实施上述代码修改
2. 添加单元测试验证修复
3. 更新文档说明回车键的行为

### 中期（v1.1.0）

1. 评估方案 2 的可行性
2. 考虑添加用户配置选项，允许禁用此功能
3. 添加更多的键盘快捷键功能

### 长期（v2.0.0）

1. 重新设计键盘事件处理机制
2. 实现更完善的快捷键系统
3. 添加快捷键自定义功能

## 测试计划

### 测试用例 1：流未启动时按回车

**前置条件**：

- 打开 Web 界面
- 显示"开启"按钮（流未启动）

**操作步骤**：

1. 按下回车键

**预期结果**：

- 视频流和音频流启动
- "开启"按钮消失

### 测试用例 2：流已启动时按回车

**前置条件**：

- 打开 Web 界面
- 视频流和音频流已启动

**操作步骤**：

1. 在远程桌面中打开文本编辑器
2. 按下回车键

**预期结果**：

- 视频流和音频流不受影响
- 远程桌面中输入换行符
- 页面不出现闪烁或冻结

### 测试用例 3：长按回车键

**前置条件**：

- 打开 Web 界面
- 显示"开启"按钮（流未启动）

**操作步骤**：

1. 长按回车键

**预期结果**：

- 只触发一次流启动
- 不会重复触发

### 测试用例 4：快速按多次回车

**前置条件**：

- 打开 Web 界面
- 视频流和音频流已启动

**操作步骤**：

1. 在远程桌面中快速按 5 次回车键

**预期结果**：

- 视频流和音频流不受影响
- 远程桌面中输入 5 个换行符
- 页面不出现闪烁或冻结

## 相关代码文件

- `addons/gstreamer-web/src/app.js` - 前端主应用文件
  - 第 172-174 行：`mounted()` 方法，添加键盘事件监听
  - 第 225-231 行：`handleKeyDown()` 方法，处理回车键事件
  - 第 232-236 行：`playStream()` 方法，启动视频和音频流

## 相关 Issue

- 无（首次报告）

## 参考资料

- [MDN: KeyboardEvent](https://developer.mozilla.org/en-US/docs/Web/API/KeyboardEvent)
- [MDN: addEventListener](https://developer.mozilla.org/en-US/docs/Web/API/EventTarget/addEventListener)
- [Vue.js: Event Handling](https://vuejs.org/guide/essentials/event-handling.html)

## 更新日志

- **2026-02-18**: Bug 首次报告和分析
- **待定**: 修复实施和验证

## 联系方式

如有问题或建议，请通过以下方式联系：

- GitHub Issues: https://github.com/open-beagle/beagle-wind-vnc/issues
- 邮件: [项目维护者邮箱]
