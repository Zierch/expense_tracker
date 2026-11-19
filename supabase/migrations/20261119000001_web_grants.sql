grant usage on schema public to authenticated;
grant select, insert, update, delete on public.categories,
  public.subcategories, public.transactions to authenticated;
grant usage, select on sequence public.categories_id_seq to authenticated;
grant usage, select on sequence public.subcategories_id_seq to authenticated;
grant usage, select on sequence public.transactions_id_seq to authenticated;
