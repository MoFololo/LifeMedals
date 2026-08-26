# LifeMedals 怪物形象生成规范

## 目标

每个怪物物种必须让用户只看轮廓和核心物件就能辨认其任务类别。勋章类别只决定物种家族，不得代替具体任务语义；例如篮球和游泳同属 Athlete，但必须是两个物种。

## 1. Taxonomy 先决定物种

- `monster_tag` 描述可复用的具体活动，不描述某一次任务。
- 已明确命名的运动必须保留项目：篮球使用 `sports.basketball`，游泳使用 `sports.swimming`，不能降级为 `fitness.workout`。
- `fitness.workout` 只用于健身房、力量训练或未指明项目的一般锻炼。
- 其他勋章遵守同样原则：倒垃圾使用 `chores.take_out_trash`，而不是宽泛的 `chores.household`。
- 标签只使用小写英文 taxonomy，不得包含用户、地点、品牌、文件、日期或其他一次性信息。

## 2. 概念模型先选 1–2 个强关联视觉锚点

概念响应必须提供 `signature_objects`，数量为 1–2。每一项必须是无需文字说明即可识别的具体物品或物理材料，不能是情绪、抽象概念、勋章图标或“通用工具”。

示例：

| Species ID | Canonical tag | 合格视觉锚点示例 |
| --- | --- | --- |
| `species-athlete-basketball` | `sports.basketball` | 篮球、篮框 |
| `species-athlete-swimming` | `sports.swimming` | 水、救生圈 |
| `species-athlete-baseball` | `sports.baseball` | 棒球、球棒 |
| `species-athlete-tennis` | `sports.tennis` | 网球、球拍 |
| `species-life-trash` | `chores.take_out_trash` | 垃圾桶、扎口垃圾袋 |

示例仅说明选择强度，模型必须根据实际 canonical tag 自行推导，不能把示例物件套到无关类别。

## 3. 每个锚点都必须融入怪物形象

- `task_features` 必须逐一描述 `signature_objects` 如何成为身体结构、主轮廓、衣着或手持/穿戴装备。
- 所有锚点都必须在单个 48×48 逻辑像素精灵中清晰可辨。
- 只放在背景、藏在场景装饰中、用动作暗示、换成文字/徽标或抽象符号，均视为未包含。
- `image_description` 必须再次明确提到每个锚点及其融合方式。
- 不得为了增加锚点而生成复杂场景；主体仍是一个居中的怪物精灵。

## 4. 九级进化保持同一物种 DNA

- 1 级只保留最强的 1–2 个锚点和最少像素块。
- 2–9 级必须保留同一张脸、身体结构、配色、像素尺度和全部视觉锚点。
- 每一级只增加一个可由像素辨认的小变化，不得通过增加无关道具改变物种含义。

## 5. 风格、安全与隐私

- 低分辨率怪诞像素吉祥物：紧凑、不对称、略笨拙但适合家庭使用。
- 硬边方形像素、阶梯轮廓、3–4 个脏灰低饱和色；禁止抗锯齿、渐变、模糊、光滑 3D 和复杂高分辨率细节。
- 禁止文字、数字、Logo、商标、受版权保护角色、血腥、裸露器官或色情内容。
- 概念与图片服务只接收 canonical tag、勋章家族、等级和稳定视觉 DNA；不得接收用户任务标题或其他私人数据。

## 6. 版本与素材不可变性

- 概念规范由 `MONSTER_CONCEPT_PROMPT_VERSION` 控制。
- 图片构图规范由 `MONSTER_PROMPT_VERSION` 控制。
- 需要重生成素材时升级 `MONSTER_STYLE_VERSION`，让新素材使用新的 variant key；旧 R2 图片保持不可变历史，不覆盖原对象。

