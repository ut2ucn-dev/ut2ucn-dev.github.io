-- Subscriptions whose "lessons left" doesn't match the lessons actually
-- taken from them.
--
-- Until sql/0023, changing an already marked lesson (discount, print,
-- payment method) took one more lesson from the subscription without
-- giving the first one back, so some subscriptions show fewer lessons left
-- than they really have.
--
-- Step 1 (only reads): run the SELECT below in Supabase → SQL Editor.
-- «Списано зайвих» > 0 means the subscription lost that many lessons.
-- Check each row before fixing it: someone may have changed «Залишок» by
-- hand on purpose (e.g. lessons carried over from paper records) — such a
-- subscription should be left as it is.

select st.name                                            as "Учень",
       s.course                                           as "Курс",
       (s.purchased_at at time zone 'UTC')::date           as "Куплено",
       s.status                                           as "Статус",
       s.total_lessons                                    as "Всього",
       s.remaining_lessons                                as "Залишок зараз",
       u.used                                             as "Відмічено занять",
       s.total_lessons - u.used                           as "Має бути залишок",
       (s.total_lessons - s.remaining_lessons) - u.used   as "Списано зайвих",
       s.id                                               as "id абонемента"
from public.subscriptions s
join public.students st on st.id = s.student_id
cross join lateral (
  select count(*)::int as used from public.lesson_attendance a
  where a.subscription_id = s.id and a.status <> 'absent'
) u
where s.status <> 'cancelled'
  and s.total_lessons - s.remaining_lessons <> u.used
order by st.name, s.purchased_at;

-- Step 2 (changes data): to fix ONE subscription from the list, put its id
-- below, remove the "--" in front of the four lines and run them.
--
-- update public.subscriptions s
--   set remaining_lessons = greatest(0, s.total_lessons - (select count(*) from public.lesson_attendance a where a.subscription_id = s.id and a.status <> 'absent')),
--       status = case when s.total_lessons - (select count(*) from public.lesson_attendance a where a.subscription_id = s.id and a.status <> 'absent') > 0 then 'active' else 'completed' end
--   where s.id = 'ВСТАВТЕ-ID-АБОНЕМЕНТА';
