-- LifeMedals v1 初始表结构
-- 用户身份由 Supabase Auth 内置的 auth.users 提供，这里只建业务表

-- ==========================================
-- 1. 勋章类别（由开发者维护，全局固定，用户只读）
-- ==========================================
create table if not exists badge_categories (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  icon       text,
  created_at timestamptz default now()
);

-- 所有登录用户可读，只有 service_role 可写
alter table badge_categories enable row level security;

create policy "read for authenticated" on badge_categories
  for select using (auth.role() = 'authenticated');

-- 默认勋章类别 seed 数据
insert into badge_categories (name, icon) values
  ('Problem Solver', '🧩'),
  ('Builder',        '🔨'),
  ('Career',         '💼'),
  ('Athlete',        '🏃'),
  ('Scholar',        '📚');

-- ==========================================
-- 2. 用户勋章（每人每个类别的 EXP + 等级）
-- ==========================================
create table if not exists user_badges (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid references auth.users on delete cascade,
  badge_category_id  uuid references badge_categories on delete cascade,
  current_xp         int not null default 0,
  level              int not null default 1,
  updated_at         timestamptz default now(),
  unique (user_id, badge_category_id)
);

alter table user_badges enable row level security;

create policy "owner access" on user_badges
  for all using (auth.uid() = user_id);

-- ==========================================
-- 3. 任务契约
-- ==========================================
create table if not exists tasks (
  id                    uuid primary key default gen_random_uuid(),
  user_id               uuid references auth.users on delete cascade,
  title                 text not null,
  deadline              timestamptz,
  -- 用户确认后锁定，AI 核验阶段不可修改
  evidence_requirement  text not null,
  badge_category_id     uuid references badge_categories on delete set null,
  xp_reward             int not null default 0,
  -- pending（执行中）| completed（已完成）| expired（已失效）
  status                text not null default 'pending',
  created_at            timestamptz default now()
);

alter table tasks enable row level security;

create policy "owner access" on tasks
  for all using (auth.uid() = user_id);

-- ==========================================
-- 4. 证据（仅保存 AI 核验通过的记录；失败时只向用户展示原因，不入库）
-- ==========================================
create table if not exists evidence (
  id           uuid primary key default gen_random_uuid(),
  task_id      uuid references tasks on delete cascade,
  image_url    text not null,
  submitted_at timestamptz default now()
);

alter table evidence enable row level security;

-- 通过 tasks 表的 user_id 验证归属
create policy "owner access" on evidence
  for all using (
    auth.uid() = (select user_id from tasks where tasks.id = evidence.task_id)
  );

-- ==========================================
-- 5. EXP 变动日志
-- ==========================================
create table if not exists xp_logs (
  id                 uuid primary key default gen_random_uuid(),
  user_id            uuid references auth.users on delete cascade,
  badge_category_id  uuid references badge_categories on delete set null,
  task_id            uuid references tasks on delete set null,
  xp_change          int not null,
  created_at         timestamptz default now()
);

alter table xp_logs enable row level security;

create policy "owner access" on xp_logs
  for all using (auth.uid() = user_id);
