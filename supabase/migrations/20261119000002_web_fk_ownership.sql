-- Keep foreign keys inside one user's data.
--
-- RLS checks the user_id of the row being written, but a plain FK to
-- categories.id does not care who owns the referenced row. Postgres FK checks
-- ignore RLS, so a user could point their own transaction at another user's
-- category: the insert succeeds, then RLS hides that category from the writer,
-- and the `categories!inner` embed makes their own row vanish from every read.
-- Pairing each FK with user_id makes that impossible.
--
-- Existing rows were checked before this was applied: no subcategory or
-- transaction points at another user's parent.

alter table public.categories
  add constraint categories_user_id_id_key unique (user_id, id);

alter table public.subcategories
  add constraint subcategories_user_id_id_key unique (user_id, id);

alter table public.subcategories
  add constraint subcategories_category_owner_fk
  foreign key (user_id, category_id) references public.categories (user_id, id);

alter table public.transactions
  add constraint transactions_category_owner_fk
  foreign key (user_id, category_id) references public.categories (user_id, id);

alter table public.transactions
  add constraint transactions_subcategory_owner_fk
  foreign key (user_id, subcategory_id) references public.subcategories (user_id, id);
