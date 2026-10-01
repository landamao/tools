# AstrBot 插件开发文档

> 基于 /root/plugins_ldmbot/ 目录下实际插件总结

---

## 一、目录结构

```
my_plugin/
├── main.py              # 【必需】插件入口文件
├── metadata.yaml        # 【推荐】插件元信息
├── _conf_schema.json    # 【可选】配置面板定义
├── requirements.txt     # 【可选】Python 依赖
├── README.md            # 【可选】说明文档
├── CHANGELOG.md         # 【可选】更新日志
├── logo.png             # 【可选】插件图标 (256x256, <200KB)
└── resources/           # 【可选】资源文件夹
```

---

## 二、main.py 基础模板

### 最小示例

```python
from astrbot.api.event import filter, AstrMessageEvent
from astrbot.api.all import Star, Context, AstrBotConfig, logger

class MyPlugin(Star):
    def __init__(self, context: Context, config: AstrBotConfig):
        super().__init__(context)
        self.config = config

    @filter.command("hello")
    async def hello_cmd(self, event: AstrMessageEvent):
        """发送 hello 时回复世界"""
        yield event.plain_result("Hello World!")
```

### 完整生命周期模板

```python
from astrbot.api.event import filter, AstrMessageEvent
from astrbot.api.all import Star, Context, AstrBotConfig, logger

class MyPlugin(Star):
    def __init__(self, context: Context, config: AstrBotConfig):
        """插件实例化（同步）"""
        super().__init__(context)
        self.config = config
        # 读取配置
        self.some_setting = config.get("some_setting", "default")

    async def initialize(self):
        """异步初始化，插件激活时调用"""
        logger.info("[MyPlugin] 初始化完成")

    async def terminate(self):
        """插件禁用/重载时调用，用于清理资源"""
        logger.info("[MyPlugin] 已停止")
```

---

## 三、装饰器详解

### 1. 命令注册 `@filter.command`

```python
# 基本命令
@filter.command("签到")
async def sign(self, event: AstrMessageEvent):
    """帮助文本（会显示在指令列表中）"""
    yield event.plain_result("签到成功！")

# 带别名
@filter.command("查询", alias={"查", "info"})
async def query(self, event: AstrMessageEvent):
    yield event.plain_result("查询结果...")

# 带参数（自动解析）
@filter.command("llm")
async def llm_cmd(self, event: AstrMessageEvent, sid: str = "", op: str = ""):
    """参数会自动从消息中解析"""
    yield event.plain_result(f"操作 {sid} {op}")

# 命令组（子命令）
@filter.command_group("typst")
def typst(self):
    pass

@typst.command("font")
async def scan_fonts(self, event: AstrMessageEvent):
    yield event.plain_result("扫描完成")
```

### 2. 权限控制 `@filter.permission_type`

```python
@filter.command("admin_cmd")
@filter.permission_type(filter.PermissionType.ADMIN)
async def admin_only(self, event: AstrMessageEvent):
    """仅管理员可用"""
    yield event.plain_result("管理员命令")
```

### 3. 消息类型监听 `@filter.event_message_type`

```python
# 监听所有消息
@filter.event_message_type(filter.EventMessageType.ALL)
async def on_all_message(self, event: AstrMessageEvent):
    pass

# 监听群消息
@filter.event_message_type(filter.EventMessageType.GROUP_MESSAGE)
async def on_group_message(self, event: AstrMessageEvent):
    pass

# 带优先级（数字越小优先级越高）
@filter.event_message_type(filter.EventMessageType.ALL, priority=-1)
async def high_priority(self, event: AstrMessageEvent):
    pass
```

### 4. 平台过滤 `@filter.platform_adapter_type`

```python
# 仅在 aiocqhttp (NapCat) 平台生效
@filter.command("qq_only")
@filter.platform_adapter_type(filter.PlatformAdapterType.AIOCQHTTP)
async def qq_command(self, event):
    pass
```

### 5. LLM 生命周期钩子

```python
import sys

# LLM 请求前（可修改 prompt）
@filter.on_llm_request(priority=100)
async def before_llm(self, event: AstrMessageEvent, req):
    req.system_prompt += "\n额外指令"
    # 阻止 LLM 调用
    # event.stop_event()

# LLM 响应后（可修改回复）
@filter.on_llm_response(priority=sys.maxsize)
async def after_llm(self, event: AstrMessageEvent, resp):
    resp.completion_text = resp.completion_text.replace("敏感词", "***")
    # 清空回复（不发送）
    # event.clear_result()
    # event.stop_event()

# 输出装饰前（最终消息发送前）
@filter.on_decorating_result(priority=-5201314)
async def before_send(self, event: AstrMessageEvent):
    result = event.get_result()
    for comp in result.chain:
        if isinstance(comp, Plain):
            comp.text = comp.text.replace("替换", "内容")
```

### 6. LLM 工具注册 `@filter.llm_tool`

```python
@filter.llm.tool("my_tool")
@filter.platform_adapter_type(filter.PlatformAdapterType.AIOCQHTTP)
async def llm_tool_example(self, event: AstrMessageEvent, arg1: str = "") -> str:
    """
    工具描述（会显示给 LLM）

    Args:
        arg1(string): 参数说明
    """
    return f"执行结果: {arg1}"
```

---

## 四、消息返回方式

### 1. 纯文本

```python
yield event.plain_result("消息内容")
```

### 2. 图片

```python
# 从文件路径
yield event.image_result("/path/to/image.png")

# 使用消息链
from astrbot.api.all import MessageChain, Image
chain = MessageChain([Image.fromFileSystem("/path/to/image.png")])
yield event.chain_result(chain)

# 从 URL
chain = MessageChain([Image.fromURL("https://example.com/img.png")])
yield event.chain_result(chain)
```

### 3. 消息链组合

```python
from astrbot.api.all import MessageChain, Plain, Image

# 文字 + 图片
chain = MessageChain([
    Plain("这是说明文字\n"),
    Image.fromFileSystem("/path/to/image.png")
])
yield event.chain_result(chain)
```

### 4. 使用 send 主动发送

```python
# 在非生成器函数中发送
await event.send(MessageChain([Plain("主动发送的消息")]))
```

---

## 五、事件对象常用方法

```python
event: AstrMessageEvent

# 获取消息文本
text = event.message_str          # 纯文本
text = event.get_message_str()    # 同上

# 获取发送者信息
user_id = event.get_sender_id()
user_name = event.get_sender_name()

# 获取群号（私聊返回 None）
group_id = event.get_group_id()

# 获取会话 ID（用于持久化）
session_id = event.unified_msg_origin

# 获取原始消息对象
raw = event.message_obj.raw_message  # OneBot 原始数据

# 停止事件传播
event.stop_event()

# 清除已有的结果
event.clear_result()
```

---

## 六、配置系统

### _conf_schema.json 格式

```json
{
  "setting_name": {
    "description": "配置项名称（显示在面板）",
    "type": "string",           // string / bool / int / float / list / text / object
    "default": "默认值",
    "hint": "配置说明（悬浮提示）"
  },
  "select_setting": {
    "description": "下拉选择",
    "type": "string",
    "options": ["选项1", "选项2"],
    "default": "选项1"
  },
  "nested_group": {
    "description": "分组名称",
    "type": "object",
    "hint": "分组说明",
    "items": {
      "sub_setting1": {
        "description": "子设置",
        "type": "string",
        "default": ""
      }
    }
  },
  "conditional": {
    "description": "条件显示",
    "type": "string",
    "default": "",
    "condition": {
      "other_setting": "some_value"  // 当 other_setting == "some_value" 时显示
    }
  }
}
```

### 读写配置

```python
# 读取
value = self.config.get("key", "default")
value = self.config["key"]

# 写入（持久化）
self.config["key"] = "new_value"
self.config.save_config()
```

---

## 七、metadata.yaml 格式

```yaml
name: plugin_id_name           # 插件标识名
display_name: 显示名称          # 面板显示名（可选）
desc: 插件描述文字              # 或用 description
version: v1.0.0
author: 作者名
repo: https://github.com/...   # 仓库地址（可选）
help: 帮助文本                  # 帮助说明（可选）
dependencies:                   # Python 依赖（可选）
  - package1
  - package2
support_platforms:              # 支持的平台（可选）
  - aiocqhttp
```

---

## 八、实用工具

### StarTools

```python
from astrbot.api.star import StarTools

# 获取插件数据目录（持久化存储）
data_dir = StarTools.get_data_dir()
# 返回: ~/.astrbot/data/plugin_data/<plugin_name>/

# 获取字体路径
font_path = StarTools.get_font_path()
```

### 日志

```python
from astrbot.api.all import logger

logger.debug("调试信息")
logger.info("普通信息")
logger.warning("警告")
logger.error("错误", exc_info=True)  # 带堆栈
```

### 定时任务（AstrBot 内置）

```python
from astrbot.api.all import AstrBotConfig

# 需要在框架层面配置，插件内暂无内置 scheduler
# 可使用 asyncio.create_task 实现简单定时
```

---

## 九、完整示例：签到插件

```python
import datetime
import random
from astrbot.api.event import filter, AstrMessageEvent
from astrbot.api.all import Star, Context, AstrBotConfig, logger

class SignPlugin(Star):
    def __init__(self, context: Context, config: AstrBotConfig):
        super().__init__(context)
        self.config = config
        self.user_data = {}  # 简单内存存储

    @filter.command("签到", alias={"sign"})
    async def sign(self, event: AstrMessageEvent):
        """每日签到获取积分"""
        user_id = event.get_sender_id()
        user_name = event.get_sender_name()
        today = datetime.date.today().isoformat()

        if user_id in self.user_data and self.user_data[user_id].get("last_sign") == today:
            yield event.plain_result(f"{user_name}，今天已经签到过啦~")
            return

        coins = random.randint(10, 100)
        self.user_data[user_id] = {
            "name": user_name,
            "last_sign": today,
            "coins": self.user_data.get(user_id, {}).get("coins", 0) + coins
        }

        yield event.plain_result(
            f"✨ {user_name} 签到成功！\n"
            f"获得 {coins} 金币\n"
            f"当前余额：{self.user_data[user_id]['coins']} 金币"
        )

    @filter.command("余额")
    async def balance(self, event: AstrMessageEvent):
        """查询当前金币余额"""
        user_id = event.get_sender_id()
        coins = self.user_data.get(user_id, {}).get("coins", 0)
        yield event.plain_result(f"当前余额：{coins} 金币")
```

---

## 十、开发注意事项

1. **中文命名**：AstrBot 插件支持中文类名、方法名、变量名
2. **异步优先**：所有事件处理方法都应是 `async def`
3. **yield 返回**：使用 `yield` 而非 `return` 返回结果
4. **错误处理**：用 try/except 包裹关键逻辑，避免插件崩溃
5. **资源清理**：在 `terminate()` 中关闭连接、释放资源
6. **配置脱敏**：不要在配置中硬编码 token，使用 `_conf_schema.json` 让用户填写
7. **图片路径**：发送图片时使用绝对路径

---

## 十一、已安装插件参考

| 插件名 | 功能 | 特点 |
|--------|------|------|
| 自定义插件 | 消息过滤、群屏蔽 | 消息拦截、配置持久化 |
| 插件元信息扫描器 | 扫描插件信息 | 命令组、模糊搜索 |
| Hermes适配器 | 与 Hermes Agent 通信 | WebSocket、HTTP服务器、LLM工具 |
| astrbot_plugin_bili_resolver | B站链接解析 | 消息监听、aiohttp |
| astrbot_plugin_help_typst | 帮助面板渲染 | Typst渲染、字体管理 |
| 空回复 | LLM 空回复拦截 | LLM钩子、统计持久化 |
| 关闭llm | 按群/私聊关闭 LLM | 权限控制、配置读写 |
| 新签到 | 每日签到系统 | SQLite、图片生成 |

---

*文档生成时间：2026-05-20*
*基于 LDMBOT 插件目录实际代码整理*
