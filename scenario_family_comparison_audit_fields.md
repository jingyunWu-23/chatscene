# scenario_family_comparison_mean_plus_variance_audit.csv 字段说明

该表用于比较不同主车模型在同一组冻结对抗车场景下的总体表现。原始 episode 级数据来自同目录下的 `combined_episode_log.csv`，审计表按以下字段分组后聚合：

```text
model_group, model_label, checkpoint_step, scenario_family
```

每一行表示一个主车 checkpoint 在一个场景族上的统计结果。本次结果中的 `scenario_family=adv_frozen_10`，表示使用 10 个冻结对抗车模型/场景进行测试。

## 聚合口径

对每个分组内的 episode 结果，统计：

```text
mean(x) = sum(x_i) / N
var(x) = sum((x_i - mean(x))^2) / N
```

这里的方差使用总体方差，即 `ddof=0`。因此表中的 `*_var` 不是样本方差。

格式化字段使用：

```text
指标_mean_var = 指标_mean ± 指标_var
```

例如：

```text
0.2700 ± 0.1971
```

表示均值为 `0.2700`，总体方差为 `0.1971`。

## 建议保留字段

论文、汇报或后续分析中建议优先保留以下字段：

| 字段 | 是否保留 | 说明 |
|---|---|---|
| `model_group` | 是 | 区分原始联合训练模型和微调模型，例如 `training_final` / `finetuned`。 |
| `model_label` | 是 | 模型名称，包含训练来源和 checkpoint step。 |
| `checkpoint_step` | 是 | 主车模型 checkpoint 的训练步数。 |
| `scenario_family` | 是 | 测试场景族，本表为 `adv_frozen_10`。 |
| `episodes` | 是 | 该模型参与统计的 episode 数。 |
| `adv_scenario_count` | 是 | 覆盖的冻结对抗车场景数量，用于检查是否完整覆盖 10 个对抗模型。 |
| `complete` | 是 | 是否完成预期测试量。通常 `episodes = adv_scenario_count * 每个对抗车测试 episode 数` 时为 `True`。 |
| `Collision rate_mean_var` | 是 | 碰撞率均值和方差，越低越好。 |
| `Road completion_mean_var` | 是 | 路线完成率均值和方差，越高越好。 |
| `Driven distance_mean_var` | 是 | 主车行驶距离均值和方差，越高通常表示存活/完成更好。 |
| `Average speed_mean_var` | 是 | 平均速度均值和方差，用于观察是否过度保守。 |
| `Traffic efficiency_mean_var` | 是 | 综合通行效率均值和方差，越高越好。 |
| `Average reward_mean_var` | 可选 | 平均奖励，依赖奖励函数设计，适合内部分析。 |

以下字段建议保留在审计版表格中，但论文主表可以不展示：

| 字段 | 用途 |
|---|---|
| `crash_mean`, `crash_var` | `Collision rate_mean_var` 的数值拆分版本。 |
| `route_completion_mean`, `route_completion_var` | `Road completion_mean_var` 的数值拆分版本。 |
| `ego_route_distance_m_mean`, `ego_route_distance_m_var` | `Driven distance_mean_var` 的数值拆分版本。 |
| `mean_speed_mean`, `mean_speed_var` | `Average speed_mean_var` 的数值拆分版本。 |
| `combined_efficiency_mean`, `combined_efficiency_var` | `Traffic efficiency_mean_var` 的数值拆分版本。 |
| `episode_reward_mean`, `episode_reward_var` | `Average reward_mean_var` 的数值拆分版本。 |

## 指标含义与计算

| 展示字段 | 数值字段 | 来源字段 | 计算方式 | 含义 |
|---|---|---|---|---|
| `Collision rate_mean_var` | `crash_mean`, `crash_var` | `crash` 或 `ego_crash` | 对 episode 碰撞布尔值取均值和方差 | 主车发生碰撞的比例。 |
| `Road completion_mean_var` | `route_completion_mean`, `route_completion_var` | `route_completion` | 对 episode 路线完成率取均值和方差 | 主车完成路线的比例，通常范围为 `[0, 1]`。 |
| `Driven distance_mean_var` | `ego_route_distance_m_mean`, `ego_route_distance_m_var` | `ego_route_distance_m` | 对 episode 主车行驶距离取均值和方差 | 主车沿路线累计行驶距离，单位为米。 |
| `Average speed_mean_var` | `mean_speed_mean`, `mean_speed_var` | `mean_speed` | 对 episode 平均速度取均值和方差 | 主车 episode 内平均速度。 |
| `Traffic efficiency_mean_var` | `combined_efficiency_mean`, `combined_efficiency_var` | `combined_efficiency` | 对 episode 综合效率取均值和方差 | 综合考虑通行进度、速度和低速惩罚后的效率指标。 |
| `Average reward_mean_var` | `episode_reward_mean`, `episode_reward_var` | `episode_reward` | 对 episode 累计奖励取均值和方差 | 主车策略在环境奖励函数下的平均累计收益。 |

## 推荐主表字段

如果只需要一个简洁表格，推荐保留：

```text
model_group,
model_label,
checkpoint_step,
scenario_family,
episodes,
adv_scenario_count,
complete,
Collision rate_mean_var,
Road completion_mean_var,
Driven distance_mean_var,
Average speed_mean_var,
Traffic efficiency_mean_var
```

如果需要支撑复核或重新画图，再保留对应的数值拆分字段：

```text
crash_mean,
crash_var,
route_completion_mean,
route_completion_var,
ego_route_distance_m_mean,
ego_route_distance_m_var,
mean_speed_mean,
mean_speed_var,
combined_efficiency_mean,
combined_efficiency_var
```

## 样例

下面是表中的一条真实记录：

| 字段 | 值 |
|---|---|
| `model_group` | `training_final` |
| `model_label` | `joint-Jul_01_14_59_59-Ego-67210` |
| `checkpoint_step` | `67210` |
| `scenario_family` | `adv_frozen_10` |
| `episodes` | `100` |
| `adv_scenario_count` | `10` |
| `complete` | `True` |
| `Collision rate_mean_var` | `0.2700 ± 0.1971` |
| `Road completion_mean_var` | `0.3753 ± 0.0725` |
| `Driven distance_mean_var` | `74.3127 ± 2844.0632` |
| `Average speed_mean_var` | `9.4726 ± 27.8262` |
| `Traffic efficiency_mean_var` | `0.2445 ± 0.0127` |
| `Average reward_mean_var` | `44.6989 ± 5956.0343` |

这表示原始联合训练主车 `checkpoint-67210.pt` 在 10 个冻结对抗车场景、共 100 个 episode 上测试后，碰撞率均值为 `0.27`，路线完成率均值为 `0.3753`，主车平均行驶距离为 `74.31 m`，平均速度为 `9.47`，综合通行效率为 `0.2445`。
