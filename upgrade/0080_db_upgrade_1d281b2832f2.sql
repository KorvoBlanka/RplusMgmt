ALTER TABLE public.clients ALTER COLUMN name DROP NOT NULL;
ALTER TABLE public.clients ALTER COLUMN login DROP NOT NULL;
ALTER TABLE public.clients ADD CONSTRAINT clients_delete_date_chk CHECK (delete_date >= add_date);

ALTER TABLE public.subscriptions ADD CONSTRAINT subscriptions_end_date_chk CHECK (end_date >= add_date);
ALTER TABLE public.subscriptions ADD CONSTRAINT subscriptions_delete_date_chk CHECK (delete_date >= add_date);

COMMENT ON TABLE address_objects IS 'Справочник адресов в формате ФИАС';
