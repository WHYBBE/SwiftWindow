# SwiftWindow

一个使用 **Swift / SwiftUI / Swift Package Manager** 编写的 macOS 小工具，用来分析
`WindowServer` 进程的内存使用明细。

`WindowServer` 由系统以 root 身份运行，普通权限无法读取它的详细内存信息，因此本工具
在“实时基础数据”之外，还提供一键以管理员权限采集 `vmmap` / `footprint` / `heap` 的完整明细。

## 功能

| 模块 | 数据来源 | 内容 |
| --- | --- | --- |
| 概览 | `ps` + `vmmap` | 实时 RSS 曲线、Physical Footprint / 峰值、虚拟内存总量、区域类型聚合（按 dirty 排序） |
| 内存区域 | `vmmap` | 每个虚拟内存区域的类型、虚拟/常驻/dirty 大小、地址范围、权限、映射文件，可搜索排序 |
| Malloc Zone | `vmmap` | 各 malloc zone 的虚拟/常驻/dirty、已分配字节、分配次数、碎片大小与碎片率 |
| 堆分配 | `heap` | 对象类 / 类型 / 所属二进制的对象数与字节数，定位堆占用大户 |
| 内存足迹 | `footprint` | Dirty / Clean / Reclaimable 分类构成与柱状图 |
| 实时数据 | `ps` | 常驻内存、虚拟内存、CPU、线程数、运行时长，支持自动刷新（3s） |

## 环境要求

- macOS 14 及以上
- Xcode 命令行工具（Swift 5.9+）

## 构建与运行

```bash
# 直接运行（开发）
swift run

# 打包成 .app 再运行（推荐）
./Scripts/make_app.sh
open .build/SwiftWindow.app
```

## 使用说明

1. 启动后应用会自动定位 `WindowServer` 的 PID，并显示实时基础数据。
2. 点击右上角 **“加载详细分析”**，系统会弹出管理员授权对话框（macOS 标准授权窗口）。
3. 授权后一次性采集 `vmmap`、`footprint`、`heap` 三份数据，切换顶部标签查看各维度明细。
4. 打开 **“自动刷新”** 可持续采样常驻内存曲线。

## 关于管理员权限与安全

- 详细内存信息必须由 root 读取，否则 `vmmap/footprint/heap` 会返回
  `you do not have appropriate privileges ... try running with sudo`。
- 本工具通过 `/usr/bin/osascript` 的 `do shell script ... with administrator privileges`
  发起授权，**只允许执行白名单内的系统诊断命令**（`vmmap`、`footprint`、`heap`、`leaks`、`sample`、`top`、`ps`），
  并会拒绝包含换行等非法参数，避免命令注入。
- 三条命令合并为一次授权，只需输入一次密码；采集结果写入临时文件后读回并清理。
- 若以 root 运行（例如 `sudo swift run`），则跳过授权提示直接采集。

## 项目结构

```
Sources/SwiftWindow/
├── SwiftWindowApp.swift          # App 入口 + 激活策略
├── Models/
│   ├── Models.swift              # 数据模型（Sendable）
│   └── Formatting.swift          # 字节格式化与大小解析
├── Services/
│   ├── Shell.swift               # 进程执行（带超时）
│   ├── WindowServerLocator.swift # 定位 PID 与基础统计
│   ├── PrivilegedRunner.swift    # 管理员权限批量执行
│   ├── VMMapParser.swift         # 解析 vmmap（区域 / 聚合 / malloc zone）
│   ├── FootprintParser.swift     # 解析 footprint 分类
│   ├── HeapParser.swift          # 解析 heap 分配明细
│   └── MonitorEngine.swift       # 状态与调度
└── Views/
    ├── ContentView.swift         # 主界面
    ├── OverviewView.swift        # 概览
    ├── RegionsView.swift         # 内存区域
    ├── ZonesView.swift           # Malloc Zone
    ├── HeapView.swift            # 堆分配
    ├── FootprintView.swift       # 内存足迹
    └── Components.swift          # 通用组件
```

## 已知限制

- `WindowServer` 受系统保护，采集时会短暂停顿该进程以读取内存（与 `sudo vmmap` 行为一致）。
- 大型进程的 `vmmap` 输出可能较大，解析在后台线程进行，界面不会卡顿。
- 工具本身不做任何网络访问，也不会上传数据。
