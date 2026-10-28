
-- =========================================================
-- Personalized Travel Itinerary Planner
-- Database: Supabase PostgreSQL
-- =========================================================

create extension if not exists pgcrypto;

-- 1. USER PROFILES
-- Linked to Supabase Authentication users.

create table if not exists public.profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    full_name text,
    avatar_url text,
    travel_style text,
    preferred_currency varchar(3) not null default 'INR',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

-- 2. TRIPS
-- Stores user preferences and trip-level information.

create table if not exists public.trips (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    title text not null,
    destination text not null,
    origin text,
    start_date date not null,
    end_date date not null,
    budget numeric(12, 2) check (budget is null or budget >= 0),
    currency varchar(3) not null default 'INR',
    travelers integer not null default 1 check (travelers > 0),
    travel_style text,
    interests text[] not null default '{}',
    accommodation_preference text,
    transportation_preference text,
    pace text not null default 'moderate'
        check (pace in ('relaxed', 'moderate', 'packed')),
    special_requirements text,
    status text not null default 'draft'
        check (status in ('draft', 'planned', 'completed', 'cancelled')),
    ai_model text,
    generation_prompt text,
    estimated_total_cost numeric(12, 2)
        check (estimated_total_cost is null or estimated_total_cost >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (end_date >= start_date)
);

-- 3. ITINERARY DAYS
-- One record per day in a trip.

create table if not exists public.itinerary_days (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid not null references public.trips(id) on delete cascade,
    day_number integer not null check (day_number > 0),
    date date not null,
    title text,
    summary text,
    estimated_cost numeric(12, 2)
        check (estimated_cost is null or estimated_cost >= 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (trip_id, day_number),
    unique (trip_id, date)
);

-- 4. ACTIVITIES
-- Attractions, restaurants, stays, and transport suggestions.

create table if not exists public.activities (
    id uuid primary key default gen_random_uuid(),
    itinerary_day_id uuid not null
        references public.itinerary_days(id) on delete cascade,
    name text not null,
    description text,
    category text not null default 'sightseeing'
        check (category in (
            'sightseeing',
            'food',
            'accommodation',
            'transport',
            'adventure',
            'culture',
            'shopping',
            'relaxation',
            'other'
        )),
    location text,
    latitude double precision,
    longitude double precision,
    start_time time,
    end_time time,
    estimated_cost numeric(12, 2)
        check (estimated_cost is null or estimated_cost >= 0),
    currency varchar(3) not null default 'INR',
    booking_url text,
    maps_url text,
    travel_time_minutes integer
        check (travel_time_minutes is null or travel_time_minutes >= 0),
    travel_notes text,
    sort_order integer not null default 0,
    is_optional boolean not null default false,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (
        latitude is null or latitude between -90 and 90
    ),
    check (
        longitude is null or longitude between -180 and 180
    ),
    check (
        start_time is null
        or end_time is null
        or end_time >= start_time
    )
);

-- 5. SAVED TRIPS
-- Bookmarks for trips a user wants to keep easily accessible.

create table if not exists public.saved_trips (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references auth.users(id) on delete cascade,
    trip_id uuid not null references public.trips(id) on delete cascade,
    created_at timestamptz not null default now(),
    unique (user_id, trip_id)
);

-- 6. TRIP COLLABORATORS
-- Supports sharing a trip with other authenticated users.

create table if not exists public.trip_collaborators (
    id uuid primary key default gen_random_uuid(),
    trip_id uuid not null references public.trips(id) on delete cascade,
    user_id uuid not null references auth.users(id) on delete cascade,
    role text not null default 'viewer'
        check (role in ('viewer', 'editor')),
    invited_by uuid references auth.users(id) on delete set null,
    created_at timestamptz not null default now(),
    unique (trip_id, user_id)
);

-- =========================================================
-- INDEXES
-- =========================================================

create index if not exists idx_trips_user_id
    on public.trips(user_id);

create index if not exists idx_trips_dates
    on public.trips(start_date, end_date);

create index if not exists idx_trips_destination
    on public.trips(destination);

create index if not exists idx_itinerary_days_trip_id
    on public.itinerary_days(trip_id);

create index if not exists idx_activities_day_id
    on public.activities(itinerary_day_id);

create index if not exists idx_saved_trips_user_id
    on public.saved_trips(user_id);

create index if not exists idx_trip_collaborators_user_id
    on public.trip_collaborators(user_id);

create index if not exists idx_trip_collaborators_trip_id
    on public.trip_collaborators(trip_id);

-- =========================================================
-- AUTOMATIC UPDATED_AT TIMESTAMPS
-- =========================================================

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists profiles_updated_at on public.profiles;
create trigger profiles_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists trips_updated_at on public.trips;
create trigger trips_updated_at
before update on public.trips
for each row execute function public.set_updated_at();

drop trigger if exists itinerary_days_updated_at on public.itinerary_days;
create trigger itinerary_days_updated_at
before update on public.itinerary_days
for each row execute function public.set_updated_at();

drop trigger if exists activities_updated_at on public.activities;
create trigger activities_updated_at
before update on public.activities
for each row execute function public.set_updated_at();

-- =========================================================
-- ROW LEVEL SECURITY
-- =========================================================

alter table public.profiles enable row level security;
alter table public.trips enable row level security;
alter table public.itinerary_days enable row level security;
alter table public.activities enable row level security;
alter table public.saved_trips enable row level security;
alter table public.trip_collaborators enable row level security;

-- Profiles: users can read and update their own profiles.

create policy "Users can view their own profile"
on public.profiles for select
to authenticated
using ((select auth.uid()) = id);

create policy "Users can insert their own profile"
on public.profiles for insert
to authenticated
with check ((select auth.uid()) = id);

create policy "Users can update their own profile"
on public.profiles for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

-- Trips: owners and collaborators can view trips.
-- Owners and editors can modify trips.

create policy "Owners and collaborators can view trips"
on public.trips for select
to authenticated
using (
    user_id = (select auth.uid())
    or exists (
        select 1
        from public.trip_collaborators c
        where c.trip_id = trips.id
          and c.user_id = (select auth.uid())
    )
);

create policy "Users can create their own trips"
on public.trips for insert
to authenticated
with check (user_id = (select auth.uid()));

create policy "Owners and editors can update trips"
on public.trips for update
to authenticated
using (
    user_id = (select auth.uid())
    or exists (
        select 1
        from public.trip_collaborators c
        where c.trip_id = trips.id
          and c.user_id = (select auth.uid())
          and c.role = 'editor'
    )
)
with check (
    user_id = (select auth.uid())
    or exists (
        select 1
        from public.trip_collaborators c
        where c.trip_id = trips.id
          and c.user_id = (select auth.uid())
          and c.role = 'editor'
    )
);

create policy "Owners can delete their trips"
on public.trips for delete
to authenticated
using (user_id = (select auth.uid()));

-- Itinerary days: inherit access from the parent trip.

create policy "Users can view accessible itinerary days"
on public.itinerary_days for select
to authenticated
using (
    exists (
        select 1 from public.trips t
        where t.id = itinerary_days.trip_id
          and (
              t.user_id = (select auth.uid())
              or exists (
                  select 1 from public.trip_collaborators c
                  where c.trip_id = t.id
                    and c.user_id = (select auth.uid())
              )
          )
    )
);

create policy "Owners and editors can create itinerary days"
on public.itinerary_days for insert
to authenticated
with check (
    exists (
        select 1 from public.trips t
        where t.id = itinerary_days.trip_id
          and (
              t.user_id = (select auth.uid())
              or exists (
                  select 1 from public.trip_collaborators c
                  where c.trip_id = t.id
                    and c.user_id = (select auth.uid())
                    and c.role = 'editor'
              )
          )
    )
);

create policy "Owners and editors can update itinerary days"
on public.itinerary_days for update
to authenticated
using (
    exists (
        select 1 from public.trips t
        where t.id = itinerary_days.trip_id
          and (
              t.user_id = (select auth.uid())
              or exists (
                  select 1 from public.trip_collaborators c
                  where c.trip_id = t.id
                    and c.user_id = (select auth.uid())
                    and c.role = 'editor'
              )
          )
    )
)
with check (
    exists (
        select 1 from public.trips t
        where t.id = itinerary_days.trip_id
          and (
              t.user_id = (select auth.uid())
              or exists (
                  select 1 from public.trip_collaborators c
                  where c.trip_id = t.id
                    and c.user_id = (select auth.uid())
                    and c.role = 'editor'
              )
          )
    )
);

create policy "Owners can delete itinerary days"
on public.itinerary_days for delete
to authenticated
using (
    exists (
        select 1 from public.trips t
        where t.id = itinerary_days.trip_id
          and t.user_id = (select auth.uid())
    )
);

-- Activities: inherit access through itinerary day and trip.

create policy "Users can view accessible activities"
on public.activities for select
to authenticated
using (
    exists (
        select 1
        from public.itinerary_days d
        join public.trips t on t.id = d.trip_id
        where d.id = activities.itinerary_day_id
          and (
              t.user_id = (select auth.uid())
              or exists (
                  select 1 from public.trip_collaborators c
                  where c.trip_id = t.id
                    and c.user_id = (select auth.uid())
              )
          )
    )
);

create policy "Owners and editors can create activities"
on public.activities for insert
to authenticated
with check (
    exists (
        select 1
        from public.itinerary_days d
        join public.trips t on t.id = d.trip_id
        where d.id = activities.itinerary_day_id
          and (
              t.user_id = (select auth.uid())
              or exists (
                  select 1 from public.trip_collaborators c
                  where c.trip_id = t.id
                    and c.user_id = (select auth.uid())
                    and c.role = 'editor'
              )
          )
    )
);

create policy "Owners and editors can update activities"
on public.activities for update
to authenticated
using (
    exists (
        select 1
        from public.itinerary_days d
        join public.trips t on t.id = d.trip_id
        where d.id = activities.itinerary_day_id
          and (
              t.user_id = (select auth.uid())
              or exists (
                  select 1 from public.trip_collaborators c
                  where c.trip_id = t.id
                    and c.user_id = (select auth.uid())
                    and c.role = 'editor'
              )
          )
    )
)
with check (
    exists (
        select 1
        from public.itinerary_days d
        join public.trips t on t.id = d.trip_id
        where d.id = t.trip_id
          and (
              t.user_id = (select auth.uid())
              or exists (
                  select 1 from public.trip_collaborators c
                  where c.trip_id = t.id
                    and c.user_id = (select auth.uid())
                    and c.role = 'editor'
              )
          )
    )
);

create policy "Owners can delete activities"
on public.activities for delete
to authenticated
using (
    exists (
        select 1
        from public.itinerary_days d
        join public.trips t on t.id = d.trip_id
        where d.id = activities.itinerary_day_id
          and t.user_id = (select auth.uid())
    )
);

-- Saved trips: each user manages their own bookmarks.

create policy "Users can view their saved trips"
on public.saved_trips for select
to authenticated
using (user_id = (select auth.uid()));

create policy "Users can save their own trips"
on public.saved_trips for insert
to authenticated
with check (
    user_id = (select auth.uid())
    and exists (
        select 1 from public.trips t
        where t.id = saved_trips.trip_id
          and (
              t.user_id = (select auth.uid())
              or exists (
                  select 1 from public.trip_collaborators c
                  where c.trip_id = t.id
                    and c.user_id = (select auth.uid())
              )
          )
    )
);

create policy "Users can unsave their trips"
on public.saved_trips for delete
to authenticated
using (user_id = (select auth.uid()));

-- Collaborators: trip owners can manage collaborators.
-- Collaborators can see their own membership.

create policy "Owners and collaborators can view memberships"
on public.trip_collaborators for select
to authenticated
using (
    user_id = (select auth.uid())
    or exists (
        select 1 from public.trips t
        where t.id = trip_collaborators.trip_id
          and t.user_id = (select auth.uid())
    )
);

create policy "Owners can add collaborators"
on public.trip_collaborators for insert
to authenticated
with check (
    exists (
        select 1 from public.trips t
        where t.id = trip_collaborators.trip_id
          and t.user_id = (select auth.uid())
    )
);

create policy "Owners can update collaborators"
on public.trip_collaborators for update
to authenticated
using (
    exists (
        select 1 from public.trips t
        where t.id = trip_collaborators.trip_id
          and t.user_id = (select auth.uid())
    )
)
with check (
    exists (
        select 1 from public.trips t
        where t.id = trip_collaborators.trip_id
          and t.user_id = (select auth.uid())
    )
);

create policy "Owners can remove collaborators"
on public.trip_collaborators for delete
to authenticated
using (
    exists (
        select 1 from public.trips t
        where t.id = trip_collaborators.trip_id
          and t.user_id = (select auth.uid())
    )
);

-- =========================================================
-- END OF SCHEMA
-- =========================================================
