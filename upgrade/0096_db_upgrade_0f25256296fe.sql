--
-- Landmarks
--
ALTER TABLE public.landmarks ADD COLUMN geojson JSON;
ALTER TABLE public.landmarks ADD COLUMN center JSON;
ALTER TABLE public.landmarks ADD COLUMN zoom INTEGER;
ALTER TABLE public.landmarks ADD COLUMN grp VARCHAR(64);
ALTER TABLE public.landmarks ADD COLUMN grp_pos INTEGER;

UPDATE public.landmarks SET geojson = metadata->'geojson', center = metadata->'center', zoom = (metadata->>'zoom')::integer, grp = metadata->>'group', grp_pos = NULLIF(metadata->>'pos', '')::integer;

COMMENT ON COLUMN public.landmarks.center IS 'Leaflet LatLng объект';
COMMENT ON COLUMN public.landmarks.grp IS 'Группа, к которой принадлежит ориентир';
COMMENT ON COLUMN public.landmarks.geojson IS 'GeoJSON данные';
COMMENT ON COLUMN public.landmarks.grp_pos IS 'Позиция внутри группы (NULL - макс)';
COMMENT ON COLUMN public.landmarks.zoom IS 'Zoom карты во время сохранения';
COMMENT ON COLUMN public.landmarks.geodata IS 'PostGIS данные';
COMMENT ON COLUMN public.landmarks.metadata IS 'Метаданные';

CREATE INDEX landmarks_grp_idx ON public.landmarks USING btree (grp);
ALTER TABLE public.landmarks ADD CONSTRAINT landmarks_delete_date_chk CHECK (delete_date >= add_date);
ALTER TABLE public.landmarks ADD CONSTRAINT landmarks_change_date_chk CHECK (change_date >= add_date);

ALTER TABLE public.landmarks ALTER COLUMN geojson SET NOT NULL;
ALTER TABLE public.landmarks ALTER COLUMN center SET NOT NULL;
ALTER TABLE public.landmarks ALTER COLUMN zoom SET NOT NULL;

--
-- Users
--
ALTER TABLE public.users ADD COLUMN public_name VARCHAR(64);
ALTER TABLE public.users ADD COLUMN public_phone_num VARCHAR(16);
ALTER TABLE public.users ADD COLUMN permissions JSON DEFAULT '{}' NOT NULL;

COMMENT ON COLUMN public.users.public_name IS 'Паблик имя';
COMMENT ON COLUMN public.users.public_phone_num IS 'Паблик номер телефона';
COMMENT ON COLUMN public.users.permissions IS 'Локальные права пользователя';

UPDATE users SET public_name = metadata->>'public_name', public_phone_num = metadata->>'public_phone_num';

--
-- Subscriptions
--
ALTER TABLE public.subscriptions ADD COLUMN realty_limit INTEGER DEFAULT 0 NOT NULL;
ALTER TABLE public.subscriptions ADD COLUMN send_owner_phone BOOLEAN DEFAULT false NOT NULL;

COMMENT ON COLUMN public.subscriptions.realty_limit IS 'Ограничение макс. количества подобранных объектов недвижимости';
COMMENT ON COLUMN public.subscriptions.send_owner_phone IS 'Отправлять в СМС номер собственника или нет';

--
-- Realty
--
ALTER TABLE public.realty RENAME COLUMN seller_id TO owner_id;
ALTER TABLE public.realty RENAME COLUMN seller_phones TO owner_phones;
ALTER TABLE public.realty RENAME COLUMN seller_info TO owner_info;
ALTER TABLE public.realty RENAME COLUMN seller_price TO owner_price;

COMMENT ON COLUMN public.realty.owner_id IS 'Собственник';
COMMENT ON COLUMN public.realty.owner_phones IS 'Контактные телефоны собственника данного объекта недвижимости';
COMMENT ON COLUMN public.realty.owner_info IS 'Доп. информация от собственника (контакты, удобное время звонка, и т.д.)';
COMMENT ON COLUMN public.realty.owner_price IS 'Цена собственника';
COMMENT ON COLUMN public.realty.price IS 'COALESCE(agency_price, owner_price)';
COMMENT ON COLUMN public.realty.delete_date IS 'Дата/время удаления';

ALTER TABLE public.realty RENAME CONSTRAINT realty_seller_fk TO realty_owner_fk;
ALTER TABLE public.realty DROP CONSTRAINT realty_seller_phones_length_chk RESTRICT;
ALTER TABLE public.realty ADD CONSTRAINT realty_owner_phones_length_chk CHECK (array_length(owner_phones, 1) > 0);
ALTER TABLE public.realty DROP CONSTRAINT realty_seller_price_chk RESTRICT;
ALTER TABLE public.realty ADD CONSTRAINT realty_owner_price_chk CHECK (owner_price > (0)::double precision);

ALTER INDEX public.realty_seller_idx RENAME TO realty_owner_idx;
ALTER INDEX public.realty_seller_phones_idx RENAME TO realty_owner_phones_idx;

ALTER TRIGGER realty_seller_phones_chk_tr ON public.realty RENAME TO realty_owner_phones_chk_tr;

CREATE OR REPLACE FUNCTION public.realty_seller_phones_chk (
)
RETURNS trigger AS'
DECLARE
  x_phone_num VARCHAR;
BEGIN
  FOREACH x_phone_num IN ARRAY NEW.owner_phones LOOP
    IF NOT (x_phone_num ~ ''^\d{10}$'') THEN
      RAISE EXCEPTION ''Invalid phone number: %'', phone_num;
      RETURN NULL;
    END IF;
  END LOOP;

  RETURN NEW;
END;
'LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY INVOKER
COST 100;

ALTER FUNCTION public.realty_seller_phones_chk() RENAME TO realty_owner_phones_chk;

CREATE OR REPLACE FUNCTION public.realty_before_update (
)
RETURNS trigger AS'
BEGIN
  -- Изменение состояния
  IF OLD.state_code != NEW.state_code THEN
    -- Обновим дату изменения состояния
    NEW.state_change_date = now();
  END IF;

  NEW.price = COALESCE(NEW.agency_price, NEW.owner_price);
  -- Изменение цены
  IF COALESCE(OLD.price, 0) != COALESCE(NEW.price, 0) THEN
      NEW.price_change_date = now();
  END IF;

  RETURN NEW;
END;
'LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY INVOKER
COST 100;

CREATE OR REPLACE FUNCTION public.realty_before_insert (
)
RETURNS trigger AS'
BEGIN
  -- Заполним price
  NEW.price = COALESCE(NEW.agency_price, NEW.owner_price);

  RETURN NEW;
END;
'LANGUAGE 'plpgsql'
VOLATILE
CALLED ON NULL INPUT
SECURITY INVOKER
COST 100;

--
-- Clients
--
ALTER TABLE public.clients ADD COLUMN description TEXT;

COMMENT ON COLUMN public.clients.description IS 'Дополнительная информация по клиенту';

UPDATE clients SET description = metadata->>'description';
